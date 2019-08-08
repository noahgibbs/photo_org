require "date"
require "json"

# TODO: date range filter
# TODO: alias tags e.g. daughter -> daughters

# A PhotoRepo is associated with an output directory where it links photos and caches various information.
# Various filters and settings are stored there, which makes it straightforward to update the
# output repo when the input directories of photos are updated.
class PhotoRepo
  INTERNAL_FIELDS = ["ingest_dirs", "photos", "tags", "filter", "link_type"]
  LINK_ALIASES = {
    "h" => "hard",
    "hard" => "hard",
    "s" => "symbolic",
    "symbolic" => "symbolic",
    "t" => "test",
    "test" => "test",
  }

  attr_reader :successful_load
  attr_reader :out_dir

  INTERNAL_FIELDS.each { |field| attr_reader field.to_sym }

  def initialize(output_dir)
    @out_dir = File.expand_path(output_dir)

    unless File.exist?(output_dir)
      raise "No such output directory as: #{output_dir.inspect}!"
    end

    @ingest_dirs = []

    @photos = {}
    @tags = []

    @link_type = "symbolic"

    @filter = {
      "required" => [],
      "disallowed" => [],
    }

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

    name.scan(/_(\w+)_/).flatten(1).map(&:downcase)
  end

  def self.file_parse(filename)
    name = File.basename(filename)  # No extension, also cut off (1), (2), etc at end

    # Default to file-create time if we don't find a better date.
    date = File.ctime(filename)

    # Default to no tags
    tags = []

    # Certain name formats contain only random numbers or serial numbers and we can ignore them.
    return date, tags if name =~ /^\d+$/
    return date, tags if name =~ /^IMAG\d+$/

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

  def always_ingest(dir)
    dir = File.expand_path(dir)
    @ingest_dirs << dir
    ingest(dir)
  end

  def clear_ingest
    @ingest_dirs = []
  end

  def ingest(dir, tags: [])
    puts "Ingest dir: #{dir.inspect}, tags: #{tags.inspect}"
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

  def add_filter(required: [], disallowed: [])
    @filter["required"] |= required
    @filter["disallowed"] |= disallowed
  end

  def set_required(new_req)
    @filter["required"] = new_req
  end

  def set_disallowed(new_dis)
    @filter["disallowed"] = new_dis
  end

  def set_link_type(new_type)
    raise "Unknown link type #{new_type.inspect} (allowed: #{LINK_ALIASES.keys.inspect})!" unless LINK_ALIASES[new_type]
    @link_type = LINK_ALIASES[new_type]
  end

  def each_photo
    @photos.each do |filename, info|
      if @filter["disallowed"].empty? || (info["tags"] & @filter["disallowed"]).empty?
        if @filter["required"].empty? || !(info["tags"] & @filter["required"]).empty?
          yield(filename, info)
        end
      end
    end
  end

  def update_links
    each_photo do |filename, info|
      old_name = filename
      new_name = "#{options[:out]}/#{info[:basename]}"

      if @link_type == "symbolic"
        File.symlink(old_name, new_name)
      elsif @link_type == "hard"
        File.link(old_name, new_name)
      elsif @link_type == "test"
        puts "Would make link: #{new_name.inspect} -> #{old_name.inspect}"
      else
        raise "Internal error! Unknown link type: #{@link_type.inspect}!"
      end
    end
  end

  # Update the cache from cached dir data and/or the directory contents
  #
  # Does the directory's mod date change when a new file is added?
  # Not sure about using that to use cached state instead of reloading...
  def update_cache
    puts "Updating cache..."
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
