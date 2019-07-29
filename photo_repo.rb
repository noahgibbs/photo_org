require "date"

class PhotoRepo
  def initialize
    @photos = {}
    @tags = []

    @filter = {
      required: [],
      disallowed: [],
    }
  end

  # For now, put tags inside underscores
  def self.tag_parse(name)
    return [] if name.strip == ""

    name.scan(/_(\w+)_/).flatten(1)
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
        tags: (tags | new_tags).sort,
        date: date,
        basename: final,
      }
    end
  end

  def filter(required: [], disallowed: [])
    @filter[:required].concat(required)
    @filter[:disallowed].concat(disallowed)
  end

  def each_photo
    @photos.each do |filename, info|
      dis = info[:tags] & @filter[:disallowed]
      if dis.empty?
        req = info[:tags] & @filter[:required]
        unless req.empty?
          yield(filename, info)
        end
      end
    end
  end
end
