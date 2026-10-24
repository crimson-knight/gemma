class Gemma
  # How many leading bytes of an upload the analyzers read. Large enough
  # for a JPEG's frame header after big EXIF and ICC segments.
  SNIFF_BYTES = 256 * 1024

  # Reads the bytes an upload's analyzers saw first, then the rest of the
  # source. Gemma reads a bounded prefix of every upload to detect its type
  # and dimensions, so it never needs to rewind the source: a socket or a
  # request body works as well as a file.
  class ReplayIO < IO
    def initialize(@prefix : Bytes, @source : IO)
      @prefix_position = 0
    end

    def read(slice : Bytes) : Int32
      remaining_prefix = @prefix.size - @prefix_position
      if remaining_prefix > 0
        count = Math.min(remaining_prefix, slice.size)
        slice.copy_from(@prefix[@prefix_position, count].to_unsafe, count)
        @prefix_position += count
        return count
      end

      @source.read(slice)
    end

    def write(slice : Bytes) : NoReturn
      raise IO::Error.new("Gemma::ReplayIO is read-only")
    end
  end

  # Counts the bytes read through it and raises `Gemma::FileTooLarge` as
  # soon as they exceed *limit* (when one is set), so an oversized upload is
  # refused while streaming instead of after it is stored.
  class SizeLimitedIO < IO
    getter bytes_read : Int64 = 0_i64

    def initialize(@source : IO, @limit : Int64?)
    end

    def read(slice : Bytes) : Int32
      count = @source.read(slice)
      @bytes_read += count
      if (limit = @limit) && @bytes_read > limit
        raise FileTooLarge.new("the file is larger than the #{limit}-byte limit")
      end
      count
    end

    def write(slice : Bytes) : NoReturn
      raise IO::Error.new("Gemma::SizeLimitedIO is read-only")
    end
  end

  # Reads up to *limit* bytes from *io* (fewer only at end of file).
  def self.read_prefix(io : IO, limit : Int32) : Bytes
    buffer = Bytes.new(limit)
    filled = 0
    while filled < limit
      count = io.read(buffer[filled, limit - filled])
      break if count == 0
      filled += count
    end
    buffer[0, filled]
  end
end
