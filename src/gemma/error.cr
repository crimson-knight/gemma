module Gemma
  # Base class for every error Gemma raises.
  class Error < Exception
  end

  # Raised when a file is not a valid IO.
  class InvalidFile < Error
    def initialize(io, missing_methods)
      super "#{io.inspect} is not a valid IO object (it doesn't respond to #{missing_methods.map { |method_name, _| "##{method_name}" }.join(", ")})"
    end
  end

  # Raised by a storage when the file it is asked for does not exist.
  class FileNotFound < Error
  end

  # Raised by the attacher when an assigned uploaded file is not cached.
  class NotCached < Error
  end

  # Raised when a location (a file id) is malformed or would resolve outside
  # its storage, such as `../../etc/hosts`.
  class InvalidLocation < Error
  end

  # Raised when a storage key has no storage registered in `Gemma.settings`.
  class StorageNotRegistered < Error
  end

  # Raised by `Gemma::Attacher#file!` when no file is attached.
  class NoFileAttached < Error
  end

  # Raised when an analyzer's external command (`file`, ImageMagick's
  # `identify`) is not installed.
  class AnalyzerMissing < Error
  end

  # Raised when an analyzer ran but could not read the file.
  class AnalyzerFailed < Error
  end

  # Raised while an upload streams, as soon as it passes the uploader's
  # `max_size`. Nothing is left in storage.
  class FileTooLarge < Error
  end
end
