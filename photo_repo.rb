require "file"

class PhotoRepo
  def initialize
    @photos = {}
  end

  def self.tag_parse(name)
    []
  end

  def self.file_parse(name)
    nil, []
  end

  def ingest(dir, tags: [])
    Dir["#{dir}/**"].each do |file|
      final = file.split("/")[-1]

      if File.directory?(file)
        new_tags = PhotoRepo.tag_parse(final)
        ingest(file, tags | new_tags)
        next
      end

      # Ingest the file, not a directory
      date, new_tags = PhotoRepo.file_parse(final)
      @photos[file] = {
        tags: (tags | new_tags).sort,
      }
    end
  end

end
