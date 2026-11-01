require "log"

require "./gemma/error"
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

    {% if plugin.constant(:FileClassMethods) %}
      class UploadedFile < Gemma::UploadedFile
        extend {{ plugin.constant(:FileClassMethods) }}
      end
    {% end %}

    {% if plugin.constant(:FileMethods) %}
      class UploadedFile < Gemma::UploadedFile
        include {{ plugin.constant(:FileMethods) }}
      end
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

    # Uploads the file to the specified storage. It delegates to `Gemma#upload`.
    #
    # ```
    # Gemma.upload(io, :store) # => #<Gemma::UploadedFile>
    # ```
    def upload(io, storage, **options)
      new(storage).upload(io, **options)
    end

    def cache(io, **options)
      new("cache").upload(io, **options)
    end

    def store(io, **options)
      new("store").upload(io, **options)
    end

    # Kept for apps that call it after configuration. Every Gemma setting
    # has a default, so there is nothing that can be missing.
    def raise_if_missing_settings! : Nil
    end

    def uploaded_file(hash : Hash(String, String | UploadedFile::MetadataType))
      uploaded_file(hash.to_json)
    end

    def uploaded_file(json : String)
      UploadedFile.from_json(json)
    end

    def uploaded_file(object : UploadedFile)
      object
    end

    # Temporarily converts an IO-like object into a file. If the input IO object
    # is already a file, it simply yields it to the block, otherwise it copies
    # IO content into a Tempfile object which is then yielded and afterwards
    # deleted.
    #
    # ```
    # Gemma.with_file(io) { |file| file.path }
    # ```
    #
    def with_file(io : IO, &)
      if io.responds_to?(:path)
        yield io
      else
        File.tempfile("gemma-file") do |file|
          File.write(file.path, io.gets_to_end)
          io.rewind
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

    # Returns the storage object referenced by the identifier.
    def storage
      self.class.find_storage(storage_key)
    end

    # Uploads *io* (an `IO`, or an `UploadedFile` on another storage) to
    # this uploader's storage and returns the stored file. Gemma never
    # closes or deletes an IO it did not open: the caller still owns *io*
    # afterwards.
    #
    # ```
    # uploader.upload(io)
    # uploader.upload(io, metadata: {"foo" => "bar"}) # add metadata
    # uploader.upload(io, location: "path/to/file")   # choose the location
    # ```
    def upload(io : IO | UploadedFile, **options) : UploadedFile
      metadata = get_metadata(io, **options)
      location = get_location(io, **options.merge(metadata: metadata))

      store_content(io, location, metadata)

      UploadedFile.new(
        id: location,
        storage_key: storage_key,
        metadata: metadata,
      )
    end

    # Returns the metadata of the file already stored at *id* on this
    # uploader's storage, read from the stored bytes. *filename* is recorded
    # as the original filename; nothing else is taken from the caller.
    def extract_stored_metadata(id : String, filename : String? = nil) : UploadedFile::MetadataType
      stored_io = storage.open(id)
      begin
        metadata = extract_metadata(stored_io)
      ensure
        stored_io.close
      end
      metadata["filename"] = filename
      metadata
    end

    # Generates a unique location for the uploaded file, preserving the
    # file extension. Can be overriden in uploaders for generating custom
    # location.
    def generate_location(io : IO | UploadedFile, metadata, **options)
      basic_location(io, metadata: metadata)
    end

    # Logs *message* as a warning on Gemma's log source.
    def warn(message : String) : Nil
      Log.warn { message }
    end

    # Extracts filename, size and MIME type from the file, which is later
    # accessible through UploadedFile#metadata.
    private def extract_metadata(io, **options) : Gemma::UploadedFile::MetadataType
      hash = Gemma::UploadedFile::MetadataType.new
      hash["filename"] = extract_filename(io)
      hash["size"] = extract_size(io)
      hash["mime_type"] = extract_mime_type(io)
      hash
    end

    # Streams *io* to the storage, leaving it open for the caller.
    private def store_content(io : IO, location : String, metadata : UploadedFile::MetadataType) : Nil
      storage.upload(io, location, metadata)
    end

    # Opens *source* on its own storage and streams it across.
    private def store_content(source : UploadedFile, location : String, metadata : UploadedFile::MetadataType) : Nil
      source_io = source.storage.open(source.id)
      begin
        storage.upload(source_io, location, metadata)
      ensure
        source_io.close
      end
    end

    # Attempts to extract the appropriate filename from the IO object.
    private def extract_filename(io) : String?
      if io.responds_to?(:original_filename)
        io.original_filename
      elsif io.responds_to?(:path)
        # Some IO types report a nilable path.
        if file_path = io.path
          File.basename(file_path.to_s)
        end
      end
    end

    # Extracts the filesize from the IO object.
    private def extract_size(io)
      io.size if io.responds_to?(:size)
    end

    # Attempts to extract the MIME type from the IO object.
    private def extract_mime_type(io : IO)
      return unless io.responds_to?(:content_type)

      declared_content_type = io.content_type
      return unless declared_content_type

      Log.warn { "The \"mime_type\" metadata comes from the client's Content-Type header, which might not hold the actual MIME type of the file. Load the determine_mime_type plugin to read it from the file content." }
      declared_content_type.split(';').first # exclude media type parameters
    end

    private def extract_mime_type(io : UploadedFile)
      io.metadata.mime_type
    end

    # Generates a basic location for an uploaded file
    private def basic_location(io, metadata : UploadedFile::MetadataType)
      extension = ".#{io.extension}" if io.is_a?(UploadedFile) && io.extension
      filename = metadata["filename"]?
      extension ||= File.extname(filename) if filename.is_a?(String)
      basename = generate_uid(io)

      extension ? basename + extension : basename
    end

    # If the IO object is a Gemma::UploadedFile, it simply copies over its
    # metadata, otherwise it calls #extract_metadata.
    private def get_metadata(io : IO, metadata : UploadedFile::MetadataType? = nil, **options)
      result = extract_metadata(io)
      result = result.merge(metadata) if metadata
      result
    end

    private def get_metadata(io : UploadedFile, metadata : UploadedFile::MetadataType? = nil, **options)
      result = io.metadata
      result = result.merge(metadata) if metadata
      result
    end

    # Retrieves the location for the given IO and context. First it looks
    # for the `:location` option, otherwise it calls #generate_location.
    private def get_location(io, location : String? = nil, **options)
      location ||= generate_location(io, **options)
      raise Error.new("location generated for #{io.inspect} was nil") if location.nil?

      location
    end

    # Generates a unique identifier that can be used for a location: 32
    # hex characters from the system's secure random source.
    def generate_uid(io) : String
      Random::Secure.hex(16)
    end
  end

  include InstanceMethods
  extend ClassMethods
end
