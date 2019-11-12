require "json"

# require "./storage/file_system"

class Shrine
  class UploadedFile
    class Metadata
      JSON.mapping(
        size: {type: UInt64, nilable: true, emit_null: true},
        mime_type: {type: String, nilable: true, emit_null: true},
        filename: {type: String, nilable: true, emit_null: true}
      )

      def initialize; end

      def initialize(data : NamedTuple)
        @size = data[:size]?.try &.to_u64
        @mime_type = data[:mime_type]?
        @filename = data[:filename]?
      end

      def data
        {
          size:      size,
          mime_type: mime_type,
          filename:  filename,
        }
      end
    end

    # getter io : IO?
    @io : IO?

    JSON.mapping(
      id: {type: String},
      storage_key: {type: String},
      metadata: {type: UploadedFile::Metadata}
    )

    def initialize(id : String, storage : String, metadata : NamedTuple = NamedTuple.new)
      @storage_key = storage
      @metadata = UploadedFile::Metadata.new(metadata)

      @id = id
    end

    def initialize(id : String, storage : Symbol, metadata : NamedTuple = NamedTuple.new)
      initialize(id, storage.to_s, metadata)
    end

    delegate size, to: @metadata
    delegate mime_type, to: @metadata
    def content_type
      mime_type
    end


    delegate pos, to: io
    delegate gets_to_end, to: io

    # delegate close, to: file
    # delegate path, to: file

    def extension
      result = File.extname(id)[1..-1]?
      result ||= File.extname(original_filename.not_nil!)[1..-1]? if original_filename
      result = result.downcase if result

      result
    end

    def original_filename
      metadata.filename if metadata
    end

    # Shorthand for accessing metadata values.
    def [](key)
      metadata[key]?
    end

    # Calls `#open` on the storage to open the uploaded file for reading.
    # Most storages will return a lazy IO object which dynamically
    # retrieves file content from the storage as the object is being read.
    #
    # If a block is given, the opened IO object is yielded to the block,
    # and at the end of the block it's automatically closed. In this case
    # the return value of the method is the block return value.
    #
    # If no block is given, the opened IO object is returned.
    #
    # ```
    # uploaded_file.open # => IO object returned by the storage
    # uploaded_file.read # => "..."
    # uploaded_file.close
    #
    # # or
    #
    # uploaded_file.open { |io| io.read } # the IO is automatically closed
    # ```
    #
    def open(**options)
      @io.not_nil!.close if @io
      @io = _open(**options)
    end

    def open(**options, &block)
      open(**options)

      begin
        yield @io.not_nil!
      ensure
        close
        @io = nil
      end
    end

    # Streams content into a newly created tempfile and returns it.
    #
    # ```
    # uploaded_file.download
    # # => #<File:/var/folders/.../20180302-33119-1h1vjbq.jpg>
    # ```
    #
    def download(**options)
      tempfile = File.tempfile("shrine", ".#{extension}")
      stream(tempfile, **options)
      tempfile.rewind
    end

    # Streams content into a newly created tempfile, yields it to the
    # block, and at the end of the block automatically closes it.
    # In this case the return value of the method is the block
    # return value.
    #
    # ```
    # uploaded_file.download { |tempfile| tempfile.gets_to_end } # tempfile is deleted
    # ```
    #
    def download(**options, &block)
      tempfile = download(**options)
      yield(tempfile)
    ensure
      if tempfile
        tempfile.not_nil!.close
        tempfile.not_nil!.delete
      end
    end

    # Streams uploaded file content into the specified destination. The
    # destination object is given directly to `IO.copy`.
    #
    # If the uploaded file is already opened, it will be simply rewinded
    # after streaming finishes. Otherwise the uploaded file is opened and
    # then closed after streaming.
    #
    # ```
    # uploaded_file.stream(IO::Memory.new)
    # ```
    def stream(destination : IO, **options)
      if opened?
        IO.copy(io, destination)
        io.rewind
      else
        open(**options) { |io| IO.copy(io, destination) }
      end
    end

    # Part of complying to the IO interface. It delegates to the internally
    # opened IO object.
    def close
      io.close if opened?
    end

    # Returns whether the file has already been opened.
    def opened?
      !!@io
    end

    # Calls `#url` on the storage, forwarding any given URL options.
    def url(**options)
      storage.url(id, options)
    end

    # Calls `#exists?` on the storage, which checks whether the file exists
    # on the storage.
    def exists?
      storage.exists?(id)
    end

    # Returns the storage that this file was uploaded to.
    def storage
      Shrine.find_storage(storage_key.not_nil!).not_nil!
    end

    def io : IO
      (@io ||= _open).not_nil!
    end

    private def _open(**options)
      storage.open(id)
    end
  end
end
