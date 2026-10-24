require "./base"

class Gemma
  module Storage
    class Memory < Storage::Base
      getter store

      def initialize
        @store = {} of String => String
      end

      def upload(io : IO | UploadedFile, id : String, move = false, **options)
        content = if io.is_a?(UploadedFile)
                    io.storage.open(io.id).gets_to_end
                  else
                    io.gets_to_end
                  end
        store[id.to_s] = content
      end

      def open(id : String) : IO
        # StringIO.new(store.fetch(id))
        IO::Memory.new(store[id])
      rescue error : KeyError
        raise Gemma::FileNotFound.new("file #{id.inspect} not found on storage", cause: error)
      end

      def open(id : String, **options) : IO
        open(id)
      end

      def exists?(id : String) : Bool
        store.has_key?(id)
      end

      def url(id : String, **options) : String
        "memory://#{path(id)}"
      end

      def path(id : String) : String
        id
      end

      def delete(id : String)
        store.delete(id)
      end

      def delete_prefixed(delete_prefix : String)
        delete_prefix = delete_prefix.chomp("/") + "/"
        store.delete_if { |key, _value| key.start_with?(delete_prefix) }
      end

      def clear!
        store.clear
      end

      protected def clean(path)
      end
    end
  end
end
