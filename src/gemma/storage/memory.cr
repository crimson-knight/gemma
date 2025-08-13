require "./base"

class Gemma
  module Storage
    class Memory < Storage::Base
      getter store

      def initialize
        @store = {} of String => String
      end

      def upload(io : IO | UploadedFile, id : String, move = false, **options)
        content = case io
                  when UploadedFile
                    # For UploadedFile, try to get content from its storage
                    # This handles the case where an UploadedFile from memory storage
                    # is being re-uploaded during GC finalization
                    begin
                      io.storage.open(io.id).gets_to_end
                    rescue Gemma::FileNotFound
                      # If file is not found (e.g., storage was cleared), use empty string
                      # This typically happens in tests when GC finalizers run after storage is cleared
                      ""
                    end
                  else
                    io.gets_to_end
                  end
        store[id.to_s] = content
      end

      def open(id : String) : IO
        # StringIO.new(store.fetch(id))
        IO::Memory.new(store[id])
      rescue KeyError
        raise Gemma::FileNotFound.new("file #{id.inspect} not found on storage")
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
