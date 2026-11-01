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
require "./gemma/uploader"
require "./gemma/plugins/*"
require "./gemma/cached_file_reference"

# File attachments for Crystal apps: uploaders stream files to named
# storages, record what the bytes are, and attach them to models.
#
# ```
# Gemma.configure do |config|
#   config.storages["cache"] = Gemma::Storage::FileSystem.new("uploads", prefix: "cache")
#   config.storages["store"] = Gemma::Storage::FileSystem.new("uploads", prefix: "store")
# end
#
# Gemma.upload(io, "store") # => #<Gemma::UploadedFile>
# ```
module Gemma
  # Gemma's log source ("gemma"). Gemma never configures logging itself;
  # the app's `Log.setup` decides where these entries go.
  Log = ::Log.for(self)

  # Returns Gemma's settings, shared by every uploader.
  def self.settings : Settings
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

  # Returns the storage registered under *name*, raising
  # `Gemma::StorageNotRegistered` if there is none.
  def self.find_storage(name : String) : Storage::Base
    settings.storages[name]? || raise StorageNotRegistered.new("storage #{name.inspect} isn't registered")
  end

  # Uploads *io* to the storage named *storage* with the base uploader.
  # See `Gemma::Uploader#upload`.
  def self.upload(io, storage : String, **options) : UploadedFile
    Uploader.new(storage).upload(io, **options)
  end

  # Uploads *io* to the "cache" storage.
  def self.cache(io, **options) : UploadedFile
    upload(io, "cache", **options)
  end

  # Uploads *io* to the "store" storage.
  def self.store(io, **options) : UploadedFile
    upload(io, "store", **options)
  end

  # Loads an `UploadedFile` from the JSON Gemma stored. Only for trusted
  # data such as a database column; a client's JSON goes through
  # `Gemma::Attacher#attach_cached`, which verifies it.
  def self.uploaded_file(json : String) : UploadedFile
    UploadedFile.from_json(json)
  end

  # Yields *io* if it is already a file, or else a tempfile holding what
  # is left of *io*, deleted after the block.
  #
  # ```
  # Gemma.with_file(io, &.path)
  # ```
  def self.with_file(io : IO, &)
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

  def self.with_file(uploaded_file : UploadedFile, &)
    uploaded_file.download do |tempfile|
      yield tempfile
    end
  end

  # Logs *message* as a warning on Gemma's log source.
  def self.warn(message : String) : Nil
    Log.warn { message }
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
end
