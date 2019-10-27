require "date"
require "json"

# TODO: date range filter
# TODO: alias tags e.g. daughter -> daughters

# TODO: better handling of multi-section underscores-and-text bits w/ no spaces - probably no tagging? Or tag all?

# A PhotoRepo is associated with an output directory where it links photos and caches various information.
# Various filters and settings are stored there, which makes it straightforward to update the
# output repo when the input directories of photos are updated.
class PhotoRepo
  INTERNAL_FIELDS = ["ingest_dirs", "photos", "tags", "filter", "order", "link_type"]
  LINK_ALIASES = {
    "h" => "hard",
    "hard" => "hard",
    "s" => "symbolic",
    "symbolic" => "symbolic",
    "t" => "test",
    "test" => "test",
    "none" => "none",
  }
  ORDERS = [ "any", "random" ]

  attr_reader :successful_load
  attr_reader :out_dir
  attr_reader :links  # Don't cache this one in JSON

  INTERNAL_FIELDS.each { |field| attr_reader field.to_sym }

  def initialize(output_dir)
    @out_dir = File.expand_path(output_dir)

    unless File.exist?(output_dir)
      raise "No such output directory as: #{output_dir.inspect}!"
    end

    @ingest_dirs = []

    @photos = {}
    @tags = []
    @links = {}

    @link_type = "symbolic"

    @filter = {
      "required" => [],
      "disallowed" => [],
      "bool_expr" => [],
    }

    @order = "any"

    if File.exist?("#{output_dir}/.prepo_cache.json")
      puts "Loading settings from cache in #{output_dir.inspect}..."
      begin
        text = File.read "#{output_dir}/.prepo_cache.json"
        restore_state JSON.load(text)
        @successful_load = true
      rescue
        puts "Can't load settings from cache due to error! #{$!.message.inspect}"
        puts "Defaulting to empty settings... Won't save settings on cache update!"
      end
    else
      puts "No cache file found in #{@out_dir.inspect}... No problem. Will save new cache after update."
      @successful_load = true
    end
  end

  # If this is called then a cache will be written after it gets updated even if there was a load error.
  def dismiss_load_error
    @successful_load = true
  end

  # For now, put tags inside underscores
  def self.tag_parse(name)
    return [] if name.strip == ""

    scanned = name.scan(/\_([^_]+)\_/)

    name.scan(/\_([^_ ][^_]+[^_ ])\_/).flatten(1).map(&:downcase)
  end

  def self.file_parse(filename)
    date, tags = filename_parse(filename)

    # Default to file-create time if we don't find a better date.
    date ||= File.ctime(filename)

    return date, tags
  end

  def self.filename_parse(filename)
    name = File.basename(filename)  # No extension, also cut off (1), (2), etc at end
    date = nil

    # Default to no tags
    tags = []

    # Certain name formats contain only (or start with) random numbers or serial numbers and we can ignore them.
    name = $' if name =~ /^(\d|_)+ ?/
    name = $' if name =~ /^IMAG\d+/

    if name =~ /^(\d{4}-\d{2}-\d{2})/
      # Starts with a date
      date = Date.parse($1)
      rest = $'

      if rest =~ /^\s*(\d{2}\.\d{2}\.\d{2})/
        # we don't store the time, we just cut it off
        rest = $'
      end

      tags = tag_parse rest
      return date, tags
    end

    tags += tag_parse(name)

    # No date in filename? Get it from file metadata.
    return date, tags
  end

  BOOL_EXPR_OPERATORS = ["|", "&", "!", "(", ")"].freeze
  BOOL_EXPR_REGEXP = /(\||\&|\!|\(|\))/

  # Return a proc representing the boolean expression or return nil if unparseable
  def bool_expr_to_proc(expr)
    tokens = expr.split(BOOL_EXPR_REGEXP).flatten(1).map(&:strip)

    code_chunks = tokens.map do |token|
      # One of the known operators? Ruby code is the same as bool_expr code
      if BOOL_EXPR_OPERATORS.include?(token)
        token
      else
        # Not an operator? It should be a tag name
        illegal_chars = token.gsub(/[a-zA-Z0-9 ]+/, "")
        unless illegal_chars == ""
          raise "Token #{token.inspect} contains illegal characters: #{illegal_chars.inspect}!"
        end
        "(info[\"tags\"].include? #{token.inspect})"
      end
    end

    ruby_code = code_chunks.join(" ")
    begin
      p = eval "proc { |info| #{ruby_code}}"
    rescue
      # Error evaluating? Return nil
      puts "Error evaluating Ruby proc from bool expr: #{expr.inspect}"
      p = nil
    end
    p
  end

  def always_ingest(dir)
    dir = File.expand_path(dir)
    @ingest_dirs |= [ dir ]
    ingest(dir)
  end

  def clear_ingest
    @ingest_dirs = []
  end

  def ingest(dir, tags: [])
    Dir["#{dir}/*"].each do |file|
      final = file.split("/")[-1]

      if File.directory?(file)
        new_tags = PhotoRepo.tag_parse(final)
        ingest(file, tags: tags | new_tags)
        next
      end

      # Ingest the file, not a directory
      date, new_tags = PhotoRepo.file_parse(file)
      @photos[file] = {
        "tags" => (tags | new_tags).sort,
        "date" => date,
        "basename" => final,
      }
    end
  end

  def internal_state
    state = {}
    INTERNAL_FIELDS.each { |field| state[field] = instance_variable_get("@#{field}") }
    state
  end

  def restore_state(new_state)
    INTERNAL_FIELDS.each do |field|
      instance_variable_set("@#{field}", new_state[field]) if new_state[field]
    end
  end

  def add_filter(required: [], disallowed: [], bool_expr: [])
    bool_expr.each do |be|
      raise "Unparseable boolean expression: #{expr.inspect}!" unless bool_expr_to_proc(be)
    end
    @filter["required"] |= required
    @filter["disallowed"] |= disallowed
    @filter["bool_expr"] |= bool_expr
  end

  def set_required(new_req)
    @filter["required"] = new_req
  end

  def set_disallowed(new_dis)
    @filter["disallowed"] = new_dis
  end

  def set_bool_expr(new_be)
    new_be.each do |be|
      raise "Unparseable boolean expression: #{expr.inspect}!" unless bool_expr_to_proc(be)
    end
    @filter["bool_expr"] = new_be
  end

  def set_link_type(new_type)
    raise "Unknown link type: #{new_type.inspect} (allowed: #{LINK_ALIASES.keys.inspect})!" unless LINK_ALIASES[new_type]
    @link_type = LINK_ALIASES[new_type]
  end

  def set_order(new_order)
    raise "Unknown order: #{new_order.inspect} (allowed: #{ORDERS.inspect})!" unless ORDERS.include?(new_order)
    @order = new_order
  end

  def each_photo
    bool_proc = nil
    if @filter["bool_expr"] == []
      bool_proc = proc { true }
    elsif @filter["bool_expr"].size == 1
      bool_proc = bool_expr_to_proc(@filter["bool_expr"][0])
    else
      bool_procs = @filter["bool_expr"].map { |be| bool_expr_to_proc(be) }
      bool_proc = proc { |file_info| bool_procs.all? { |bp| bp.call(file_info) } }
    end

    @photos.each do |filename, info|
      if @filter["disallowed"].empty? || (info["tags"] & @filter["disallowed"]).empty?
        if @filter["required"].empty? || (info["tags"] & @filter["required"]).size == @filter["required"].size
          if @filter["bool_expr"].empty? || bool_proc.call(info)
            yield(filename, info)
          end
        end
      end
    end
  end

  def matching_photos
    matching = []
    each_photo { |filename, info| matching.push([filename, info]) }
    matching
  end

  # This takes a list of filename/info array pairs and returns it in
  # (potentially) a different order
  def reordered(photo_name_info_list)
    return photo_name_info_list if @order == "any"
    return photo_name_info_list.sample(photo_name_info_list.size) if @order == "random"

    raise "Unrecognized order: #{@order}!"
  end

  def update_links
    # Remove previous links
    Dir["#{@out_dir}/photo_*"].each do |link_filename|
      File.unlink(link_filename)
    end
    @links = {}

    reordered(matching_photos).each.with_index do |(filename, info), index|
      old_name = filename
      extension = File.extname(filename)
      new_name = "#{@out_dir}/photo_#{index}#{extension}"

      @links[old_name] = new_name
      if @link_type == "symbolic"
        File.symlink(old_name, new_name)
      elsif @link_type == "hard"
        File.link(old_name, new_name)
      elsif @link_type == "test"
        puts "Would make link: #{new_name.inspect} -> #{old_name.inspect}"
      elsif @link_type == "none"
        # Do nothing
      else
        raise "Internal error! Unknown link type: #{@link_type.inspect}!"
      end
    end
    puts "Updated #{matching_photos.size} links to photos..."
  end

  # Update the cache from cached dir data and/or the directory contents
  #
  # Does the directory's mod date change when a new file is added?
  # Not sure about using that to use cached state instead of reloading...
  def update_cache
    puts "Updating cache..."
    @photos = {}
    @tags = []
    @ingest_dirs.each do |i|
      ingest(i)
    end

    # Only write out settings cache if the program loaded successfully
    if @successful_load
      puts "Saving cache to #{@out_dir}/.prepo_cache.json"
      File.open("#{@out_dir}/.prepo_cache.json", "w") do |f|
        f.print(JSON.dump internal_state)
      end
    end
  end
end
