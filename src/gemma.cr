require "log"

require "./gemma/error"
require "./gemma/metadata"
require "./gemma/filename"
require "./gemma/streaming"
require "./gemma/analyzers/*"
require "./gemma/settings"
require "./gemma/storage/*"
require "./gemma/attacher"
require "./gemma/uploaded_file"
require "./gemma/cached_file_reference"

class Gemma
  # Gemma's log source ("gemma"). Gemma never configures logging itself;
  # the app's `Log.setup` decides where these entries go.
  Log = ::Log.for(self)

  PLUGINS = [] of Nil

  # Returns Gemma's settings. Subclasses share the settings of `Gemma`.
  def self.settings : Settings
    SETTINGS
  end

  # :ditto:
  def settings : Settings
    SETTINGS
  end

  # Yields the settings for configuration at boot.
  #
  # ```
  # Gemma.configure do |config|
  #   config.storages["store"] = Gemma::Storage::FileSystem.new("uploads")
  # end
  # ```
  def self.configure(&) : Nil
    yield settings
  end

  struct PluginSettings
    def all
      [] of Nil
    end
  end

  def self.plugin_settings
    PluginSettings.new
  end

  macro inherited
    {{ @type }}::PLUGINS = [] of Nil

    {% for plugin in @type.superclass.constant(:PLUGINS) %}
      load_plugin({{ plugin[:decl] }}, {{ plugin[:options].double_splat }})
    {% end %}

    class Attacher < Gemma::Attacher
      def self.gemma_class
        {{ @type }}
      end
    end

    # class UploadedFile
    #   def self.gemma_class
    #     {{ @type }}
    #   end
    # end
  end

  macro load_plugin(plugin, **args)
    {% plugin = plugin.resolve %}
    {% options = args %}

    {% if PLUGINS.map { |e| e[:decl] }.includes?(plugin) %}
      raise ArgumentError.new("Cannot load plugin {{ plugin.stringify }} to {{ @type }}. Plugin has already been initialized")
    {% else %}
      {% if plugin.constant(:DEFAULT_OPTIONS) %}
        {% if !options %}
          {% options = plugin.constant(:DEFAULT_OPTIONS) %}
        {% end %}

        {% for key in plugin.constant(:DEFAULT_OPTIONS).keys %}
          {% unless options[key] %}
            {{ options[key] = plugin.constant(:DEFAULT_OPTIONS)[key] }}
          {% end %}
        {% end %}
      {% end %}

      {% PLUGINS << {decl: plugin, options: options} %}
    {% end %}

    {% if plugin.constant(:InstanceMethods) %}
      include {{ plugin.constant(:InstanceMethods) }}
    {% end %}

    {% if plugin.constant(:ClassMethods) %}
      extend {{ plugin.constant(:ClassMethods) }}
    {% end %}

    {% if plugin.constant(:AttacherClassMethods) %}
      class Attacher < Gemma::Attacher
        extend {{ plugin.constant(:AttacherClassMethods) }}
      end
    {% end %}

    {% if plugin.constant(:AttacherMethods) %}
      class Attacher < Gemma::Attacher
        include {{ plugin.constant(:AttacherMethods) }}
      end
    {% end %}
  end

  macro finalize_plugins!
    class PluginsSettings
      def all
        {% if @type.constant(:PLUGINS) %}
          {{
            @type.constant(:PLUGINS).map do |plugin|
              options = (plugin[:options].empty? ? nil : plugin[:options])

              {
                name:    plugin[:decl].stringify.underscore.split("::").last,
                options: options,
              }
            end
          }}
        {% end %}
      end

      def [](key : Symbol | String)
        all.find{ |plugin| plugin[:name] == key.to_s}.try &.[:options]
      end

      {% for plugin in @type.constant(:PLUGINS) %}
        def {{ plugin[:decl].stringify.underscore.split("::").last.id }}
          {% if plugin[:options].empty? %}
            nil
          {% else %}
            {{ plugin[:options] }}
          {% end %}
        end
      {% end %}
    end

    def self.plugin_settings
      PluginsSettings.new
    end
  end

  module ClassMethods
    # Returns the storage registered under *name*, raising
    # `Gemma::StorageNotRegistered` if there is none.
    def find_storage(name : String) : Storage::Base
      settings.storages[name]? || raise StorageNotRegistered.new("storage #{name.inspect} isn't registered on #{self}")
    end

    # Uploads *io* to the storage named *storage*. See `Gemma#upload`.
    #
    # ```
    # Gemma.upload(io, "store") # => #<Gemma::UploadedFile>
    # ```
    def upload(io, storage : String, **options) : UploadedFile
      new(storage).upload(io, **options)
    end

    # Uploads *io* to the "cache" storage.
    def cache(io, **options) : UploadedFile
      new("cache").upload(io, **options)
    end

    # Uploads *io* to the "store" storage.
    def store(io, **options) : UploadedFile
      new("store").upload(io, **options)
    end

    # Kept for apps that call it after configuration. Every Gemma setting
    # has a default, so there is nothing that can be missing.
    def raise_if_missing_settings! : Nil
    end

    # Loads an `UploadedFile` from the JSON Gemma stored. Only for trusted
    # data such as a database column; a client's JSON goes through
    # `Gemma::Attacher#attach_cached`, which verifies it.
    def uploaded_file(json : String) : UploadedFile
      UploadedFile.from_json(json)
    end

    def uploaded_file(object : UploadedFile) : UploadedFile
      object
    end

    # Yields *io* if it is already a file, or else a tempfile holding what
    # is left of *io*, deleted after the block.
    #
    # ```
    # Gemma.with_file(io, &.path)
    # ```
    def with_file(io : IO, &)
      if io.is_a?(File)
        yield io
      else
        File.tempfile("gemma-file") do |file|
          IO.copy(io, file)
          file.rewind
          yield file
        end
      end
    end

    def with_file(uploaded_file : UploadedFile, &)
      uploaded_file.download do |tempfile|
        yield tempfile
      end
    end

    # Logs *message* as a warning on Gemma's log source.
    def warn(message : String) : Nil
      Log.warn { message }
    end
  end

  module InstanceMethods
    getter storage_key : String

    def initialize(@storage_key : String)
    end

    # Returns the storage this uploader writes to.
    def storage : Storage::Base
      self.class.find_storage(storage_key)
    end

    # The largest upload this uploader accepts, in bytes, or nil for no
    # limit. Override it in an uploader:
    #
    # ```
    # class AvatarUploader < Gemma
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
      extracted = extract_metadata(prefix, client_metadata)
      store_stream(ReplayIO.new(prefix, io), location || generate_location(extracted), extracted, max_size)
    end

    # Copies *source* (a file on another storage) to this uploader's
    # storage, keeping its metadata and recounting its size.
    def upload(source : UploadedFile, *, location : String? = nil, max_size : Int64? = self.max_size) : UploadedFile
      source_io = source.storage.open(source.id)
      begin
        store_stream(source_io, location || generate_location(source.metadata), source.metadata, max_size)
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
        metadata = extract_metadata(prefix, Metadata.new(filename: Filename.sanitize(filename)))
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

    # Detects the MIME type from the first bytes with the built-in
    # magic-byte sniffer. Plugins may override it.
    def detect_mime_type(prefix : Bytes, metadata : Metadata) : String?
      Analyzers::MagicBytes.mime_type(prefix)
    end

    # Logs *message* as a warning on Gemma's log source.
    def warn(message : String) : Nil
      Log.warn { message }
    end

    private def store_stream(io : IO, location : String, metadata : Metadata, max_size : Int64?) : UploadedFile
      body = SizeLimitedIO.new(io, max_size)
      begin
        storage.upload(body, location, metadata)
      rescue error : FileTooLarge
        storage.delete(location)
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

    private def count_remaining_bytes(io : IO) : Int64
      buffer = Bytes.new(64 * 1024)
      total = 0_i64
      while (count = io.read(buffer)) > 0
        total += count
      end
      total
    end
  end

  # The client's filename for *io*: its `original_filename` (multipart
  # parts and similar wrappers), or else the basename of its `path`.
  def self.client_filename(io : IO) : String?
    if io.responds_to?(:original_filename)
      io.original_filename.try(&.to_s)
    elsif io.responds_to?(:path)
      # Some IO types report a nilable path.
      if file_path = io.path
        File.basename(file_path.to_s)
      end
    end
  end

  # The client's declared `Content-Type` for *io*, without parameters.
  def self.declared_content_type(io : IO) : String?
    return unless io.responds_to?(:content_type)

    declared = io.content_type
    media_type(declared.to_s) if declared
  end

  # The media type of a `Content-Type` value, lowercased and without
  # parameters: `"Text/Plain; charset=utf-8"` gives `"text/plain"`.
  def self.media_type(content_type : String) : String?
    content_type.split(';').first.strip.downcase.presence
  end

  include InstanceMethods
  extend ClassMethods
end
