module Gemma
  # The base uploader. An app's uploaders subclass it, override its methods
  # (`max_size`, `generate_location`, `custom_metadata`) and include plugin
  # modules:
  #
  # ```
  # class AvatarUploader < Gemma::Uploader
  #   include Gemma::Plugins::StoreDimensions
  #
  #   def max_size : Int64?
  #     5_000_000_i64
  #   end
  # end
  #
  # AvatarUploader.upload(io, "store").metadata.width # => 300
  # ```
  class Uploader
    # Uploads *io* to the storage named *storage*. See `#upload`.
    def self.upload(io, storage : String, **options) : UploadedFile
      new(storage).upload(io, **options)
    end

    # The base uploader's attacher.
    class Attacher < Gemma::Attacher
    end

    # Each uploader gets its own `Attacher` subclass, which uploads with it.
    macro inherited
      class Attacher < Gemma::Attacher
        def self.uploader_class : Gemma::Uploader.class
          {{ @type }}
        end
      end
    end

    # Removed in Gemma 0.7: plugins are modules now.
    @[Deprecated("Include the plugin module instead; see the compile error.")]
    macro load_plugin(plugin, **options)
      {% name = plugin.stringify %}
      {% if name.ends_with?("AddMetadata") %}
        {% raise "Gemma 0.7 removed load_plugin. AddMetadata is now a method: override `def custom_metadata(io : IO, metadata : Gemma::Metadata) : Hash(String, String)` in your uploader." %}
      {% elsif name.ends_with?("Column") %}
        {% raise "Gemma 0.7 removed load_plugin. The Column plugin is built in: use `Attacher.from_column`, `Attacher#load_column` and `Attacher#column_data`." %}
      {% else %}
        {% raise "Gemma 0.7 removed load_plugin. Include the plugin module in your uploader instead: `include #{name.id}`, and pick an analyzer by overriding its class method (see the plugin's documentation)." %}
      {% end %}
    end

    # Removed in Gemma 0.7 with `load_plugin`.
    @[Deprecated("Delete the call; plugins are modules now.")]
    macro finalize_plugins!
      {% raise "Gemma 0.7 removed finalize_plugins!: plugins are included modules, so there is nothing to finalize. Delete the call." %}
    end

    getter storage_key : String

    def initialize(@storage_key : String)
    end

    # Returns the storage this uploader writes to.
    def storage : Storage::Base
      Gemma.find_storage(storage_key)
    end

    # The largest upload this uploader accepts, in bytes, or nil for no
    # limit. Override it in an uploader:
    #
    # ```
    # class AvatarUploader < Gemma::Uploader
    #   def max_size : Int64?
    #     5_000_000_i64
    #   end
    # end
    # ```
    def max_size : Int64?
      nil
    end

    # Streams *io* to this uploader's storage and returns the stored file.
    #
    # Gemma reads the first bytes to detect the MIME type (and, with
    # plugins, dimensions), counts the bytes as they stream, and raises
    # `Gemma::FileTooLarge` past *max_size*, leaving nothing in storage. It
    # never rewinds, closes or deletes *io*, so a pipe or a request body
    # works and the caller still owns *io* afterwards.
    #
    # - *filename*: the client's filename (otherwise read from the IO's
    #   `original_filename` or `path`); it is sanitized.
    # - *declared_content_type*: the client's `Content-Type`, recorded as
    #   `extra["declared_content_type"]` and never used as the MIME type.
    # - *metadata*: custom fields. Only `filename` and custom keys are taken;
    #   `size`, `mime_type`, `width` and `height` always come from the bytes.
    # - *location*: where to store it; by default a random name with an
    #   extension that matches the detected type.
    #
    # ```
    # uploader.upload(io)
    # uploader.upload(io, filename: "photo.jpg", metadata: {"album" => "trips"})
    # ```
    def upload(io : IO, *, location : String? = nil, filename : String? = nil, declared_content_type : String? = nil, metadata : Hash(String, String)? = nil, max_size : Int64? = self.max_size) : UploadedFile
      client_filename = filename || Gemma.client_filename(io)
      prefix = Gemma.read_prefix(io, SNIFF_BYTES)
      client_metadata = Metadata.new(filename: Filename.sanitize(client_filename))
      declared = declared_content_type || Gemma.declared_content_type(io)
      if declared && (media_type = Gemma.media_type(declared))
        client_metadata.extra["declared_content_type"] = media_type
      end
      client_metadata = merge_caller_metadata(client_metadata, metadata)
      extracted = analyze(prefix, client_metadata)
      store_stream(ReplayIO.new(prefix, io), location || generate_location(extracted), extracted, max_size)
    end

    # Copies *source* (a file on another storage) to this uploader's
    # storage. Its bytes are analyzed again, as for any upload; only its
    # original filename and custom fields carry over.
    def upload(source : UploadedFile, *, location : String? = nil, max_size : Int64? = self.max_size) : UploadedFile
      source_io = source.storage.open(source.id)
      begin
        upload(source_io, location: location, filename: source.original_filename, metadata: source.metadata.extra, max_size: max_size)
      ensure
        source_io.close
      end
    end

    # Uploads a multipart part: anything shaped like `Amber::Router::File`
    # (`#file`, `#filename`, `#headers`). The client's original filename
    # and `Content-Type` come from the part, not from the tempfile's name.
    def upload(part, *, location : String? = nil, metadata : Hash(String, String)? = nil, max_size : Int64? = self.max_size) : UploadedFile
      upload(part.file, location: location, filename: part.filename, declared_content_type: part.headers["Content-Type"]?, metadata: metadata, max_size: max_size)
    end

    # Returns the metadata of the file already stored at *id* on this
    # uploader's storage, read from the stored bytes. *filename* is recorded
    # as the original filename; nothing else is taken from the caller.
    def extract_stored_metadata(id : String, filename : String? = nil) : Metadata
      stored_io = storage.open(id)
      begin
        prefix = Gemma.read_prefix(stored_io, SNIFF_BYTES)
        metadata = analyze(prefix, Metadata.new(filename: Filename.sanitize(filename)))
        metadata.size = prefix.size.to_i64 + count_remaining_bytes(stored_io)
        metadata
      ensure
        stored_io.close
      end
    end

    # Generates a location: 32 random hex characters, plus an extension
    # that matches the detected MIME type. Override it to choose your own.
    def generate_location(metadata : Metadata) : String
      basename = generate_uid
      extension = location_extension(metadata)
      extension ? "#{basename}.#{extension}" : basename
    end

    # 32 hex characters from the system's secure random source.
    def generate_uid : String
      Random::Secure.hex(16)
    end

    # Fills *metadata* from the upload's first bytes (*prefix*, at most
    # `SNIFF_BYTES`). *metadata* arrives holding the client's filename,
    # declared content type and custom fields. The base uploader detects
    # the MIME type; plugins add to it and call `super`.
    def extract_metadata(prefix : Bytes, metadata : Metadata) : Metadata
      metadata.mime_type = detect_mime_type(prefix, metadata)
      metadata
    end

    # Custom fields to store with each upload, computed from its first bytes
    # (*io*, at most `SNIFF_BYTES`) and *metadata*, a copy of everything
    # found before it (plugins included, so `width` is set for an image with
    # `StoreDimensions`). Override it in an uploader; the base uploader adds
    # none. Built-in fields (`size`, `mime_type`, `width`, `height`,
    # `filename`) come from the file: returning them, or changing them on
    # the copy, has no effect.
    #
    # ```
    # class DocumentUploader < Gemma::Uploader
    #   def custom_metadata(io : IO, metadata : Gemma::Metadata) : Hash(String, String)
    #     {"first_line" => io.gets || ""}
    #   end
    # end
    # ```
    def custom_metadata(io : IO, metadata : Metadata) : Hash(String, String)
      Hash(String, String).new
    end

    # Detects the MIME type from the first bytes with the built-in
    # magic-byte sniffer. Plugins may override it.
    def detect_mime_type(prefix : Bytes, metadata : Metadata) : String?
      Analyzers::MagicBytes.mime_type(prefix)
    end

    private def store_stream(io : IO, location : String, metadata : Metadata, max_size : Int64?) : UploadedFile
      body = SizeLimitedIO.new(io, max_size)
      # Gemma's storages write nothing when an upload fails; a custom one
      # may leave part of the file. Remove that, but never a file that was
      # at *location* before (a `replace` that was too large).
      location_was_free = max_size.nil? || !storage.exists?(location)
      begin
        storage.upload(body, location, metadata)
      rescue error : FileTooLarge
        storage.delete(location) if location_was_free
        raise error
      end

      stored_metadata = metadata
      stored_metadata.extra = metadata.extra.dup
      stored_metadata.size = body.bytes_read
      UploadedFile.new(location, storage_key, stored_metadata)
    end

    # Takes the caller's `filename` and custom fields; drops built-in fields,
    # which only the bytes may set.
    private def merge_caller_metadata(metadata : Metadata, caller_metadata : Hash(String, String)?) : Metadata
      return metadata unless caller_metadata

      caller_metadata.each do |key, value|
        if key == "filename"
          metadata.filename = Filename.sanitize(value)
        elsif Metadata::BUILT_IN_KEYS.includes?(key)
          Log.debug { "ignored caller metadata #{key.inspect}: Gemma reads it from the file" }
        else
          metadata.extra[key] = value
        end
      end
      metadata
    end

    # The extension for a generated location: the client's extension when
    # it is a usual one for the detected type, else the type's canonical
    # extension. An unknown type gets none, so an upload of unknown content
    # can never be stored as `.html`.
    private def location_extension(metadata : Metadata) : String?
      mime_type = metadata.mime_type
      return unless mime_type

      client_extension = metadata.filename.try { |name| File.extname(name).lchop('.').downcase }
      if client_extension && client_extension.matches?(/\A[a-z0-9]{1,10}\z/) && Analyzers::MagicBytes.extension_matches?(client_extension, mime_type)
        client_extension
      else
        Analyzers::MagicBytes.extension_for(mime_type)
      end
    end

    # Runs the analyzers (`extract_metadata`, with plugins), then adds the
    # uploader's `custom_metadata`.
    private def analyze(prefix : Bytes, metadata : Metadata) : Metadata
      extracted = extract_metadata(prefix, metadata)
      view = extracted
      view.extra = extracted.extra.dup
      add_custom_metadata(extracted, custom_metadata(IO::Memory.new(prefix, writable: false), view))
      extracted
    end

    private def add_custom_metadata(metadata : Metadata, fields : Hash(String, String)) : Nil
      fields.each do |key, value|
        if Metadata::BUILT_IN_KEYS.includes?(key)
          Log.warn { "#{self.class}#custom_metadata returned #{key.inspect}, which Gemma reads from the file; ignored" }
        else
          metadata.extra[key] = value
        end
      end
    end

    private def count_remaining_bytes(io : IO) : Int64
      buffer = Bytes.new(64 * 1024)
      total = 0_i64
      while (count = io.read(buffer)) > 0
        total += count
      end
      total
    end
  end
end
