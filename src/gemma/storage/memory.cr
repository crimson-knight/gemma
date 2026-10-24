require "./base"

class Gemma
  module Storage
    # Keeps files in a hash in memory, for specs and development. Access is
    # synchronized, so fibers on several threads can share one instance.
    class Memory < Storage::Base
      @mutex = Mutex.new

      def initialize
        @store = {} of String => Bytes
      end

      # Returns a copy of the stored files keyed by id.
      def store : Hash(String, Bytes)
        @mutex.synchronize { @store.dup }
      end

      def upload(io : IO, id : String, metadata : UploadedFile::MetadataType = UploadedFile::MetadataType.new) : Nil
        content = io.getb_to_end
        @mutex.synchronize { @store[id] = content }
      end

      def open(id : String) : IO
        content = @mutex.synchronize { @store[id]? }
        raise Gemma::FileNotFound.new("file #{id.inspect} not found on storage") unless content

        IO::Memory.new(content, writable: false)
      end

      def exists?(id : String) : Bool
        @mutex.synchronize { @store.has_key?(id) }
      end

      def url(id : String, **options) : String
        "memory://#{id}"
      end

      def delete(id : String) : Nil
        @mutex.synchronize { @store.delete(id) }
        nil
      end

      # Deletes every file whose id starts with *delete_prefix* followed by
      # `/`.
      def delete_prefixed(delete_prefix : String) : Nil
        directory_prefix = delete_prefix.chomp("/") + "/"
        @mutex.synchronize { @store.reject! { |key, _value| key.starts_with?(directory_prefix) } }
        nil
      end

      def clear! : Nil
        @mutex.synchronize { @store.clear }
      end
    end
  end
end
