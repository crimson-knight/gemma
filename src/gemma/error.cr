class Gemma
  # Base class for every error Gemma raises.
  class Error < Exception; end

  # Raised when a file is not a valid IO.
  class InvalidFile < Error
    def initialize(io, missing_methods)
      super "#{io.inspect} is not a valid IO object (it doesn't respond to #{missing_methods.map { |method_name, _| "##{method_name}" }.join(", ")})"
    end
  end

  # Raised by the storage in the #open method.
  class FileNotFound < Error
  end

  # Raised by the attacher when assigned uploaded file is not cached.
  class NotCached < Error
  end
end
