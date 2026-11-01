require "json"
require "./metadata"

class Gemma
  # A file Gemma stored: where it is (`id` on the storage named
  # `storage_key`) and what Gemma knows about it (`metadata`). It is a
  # plain value; opening it returns a new IO each time, which the caller
  # closes (or use the block forms).
  #
  # Its JSON is the shape Gemma has always stored:
  # `{"id": "...", "storage_key": "store", "metadata": {...}}`.
  struct UploadedFile
    include JSON::Serializable

    getter id : String
    getter storage_key : String
    getter metadata : Metadata = Metadata.new

    def initialize(@id : String, @storage_key : String, @metadata : Metadata = Metadata.new)
    end

    # Size in bytes, counted while the file was stored.
    def size : Int64?
      metadata.size
    end

    # MIME type detected from the file's content.
    def mime_type : String?
      metadata.mime_type
    end

    # :ditto:
    def content_type : String?
      mime_type
    end

    # Image width in pixels, read from the file's header (with the
    # `StoreDimensions` plugin).
    def width : Int32?
      metadata.width
    end

    # Image height in pixels, read from the file's header.
    def height : Int32?
      metadata.height
    end

    # `{width, height}` when both are known.
    def dimensions : {Int32, Int32}?
      metadata.dimensions
    end

    # The client's original filename, sanitized.
    def original_filename : String?
      metadata.filename
    end

    # The lowercase extension of the id, or else of the original filename.
    def extension : String?
      result = File.extname(id)[1..-1]?
      if !result && (filename = original_filename)
        result = File.extname(filename)[1..-1]?
      end
      result.try(&.downcase)
    end

    # Opens the file on its storage. The caller closes the returned IO.
    def open : IO
      storage.open(id)
    end

    # Opens the file, yields the IO, and closes it after the block.
    #
    # ```
    # uploaded_file.open(&.gets_to_end) # => "..."
    # ```
    def open(& : IO -> T) : T forall T
      io = open
      begin
        yield io
      ensure
        io.close
      end
    end

    # Streams the file into a new tempfile and returns it rewound. The caller
    # owns the tempfile and deletes it; if streaming fails, it is deleted
    # here.
    def download : File
      suffix = extension.try { |found| ".#{found}" }
      tempfile = File.tempfile("gemma", suffix)
      begin
        stream(tempfile)
        tempfile.rewind
      rescue error
        tempfile.delete
        tempfile.close
        raise error
      end
      tempfile
    end

    # Downloads the file to a tempfile, yields it, and closes and deletes it
    # after the block.
    def download(& : File -> T) : T forall T
      tempfile = download
      begin
        yield tempfile
      ensure
        tempfile.close
        tempfile.delete
      end
    end

    # Copies the file's content into *destination*.
    def stream(destination : IO) : Nil
      open { |io| IO.copy(io, destination) }
    end

    # The storage's URL for the file; options go to the storage.
    def url(**options) : String
      storage.url(id, **options)
    end

    def exists? : Bool
      storage.exists?(id)
    end

    # Uploads *io* to this file's location and returns the new file.
    def replace(io : IO) : UploadedFile
      uploader.upload(io, location: id)
    end

    def delete : Nil
      storage.delete(id)
    end

    # An uploader for this file's storage.
    def uploader : Gemma
      Gemma.new(storage_key)
    end

    def storage : Gemma::Storage::Base
      Gemma.find_storage(storage_key)
    end

    # Two uploaded files are equal when they name the same file: the same id
    # on the same storage.
    def ==(other : UploadedFile) : Bool
      id == other.id && storage_key == other.storage_key
    end
  end
end
