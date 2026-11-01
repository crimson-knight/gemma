require "json"

class Gemma
  # A client's claim that it holds a file Gemma cached earlier: the JSON a
  # form sends back (`{"id": "...", "storage_key": "cache", "metadata": {...}}`)
  # so a re-rendered form does not upload the file again.
  #
  # It is untrusted input. Only the id, the storage key and the original
  # filename are read from it; `Gemma::Attacher#attach_cached` then checks
  # that the id is one the cache could have issued, that the file exists in
  # the cache, and reads size and MIME type from the stored bytes.
  struct CachedFileReference
    include JSON::Serializable

    # The part of the client's metadata Gemma keeps.
    struct ClientMetadata
      include JSON::Serializable

      getter filename : String? = nil

      def initialize(@filename : String? = nil)
      end
    end

    getter id : String
    getter storage_key : String
    getter metadata : ClientMetadata = ClientMetadata.new

    def initialize(@id : String, @storage_key : String, @metadata : ClientMetadata = ClientMetadata.new)
    end

    # Parses *json*, raising `Gemma::NotCached` when it is not a reference.
    def self.parse(json : String) : CachedFileReference
      from_json(json)
    rescue error : JSON::Error
      raise NotCached.new("expected a cached file reference", cause: error)
    end

    # Returns whether *id* has the shape of a location Gemma generates:
    # "/"-separated segments of letters, digits, `_`, `-` and `.`, none
    # starting with a dot, so no segment can be `.` or `..`.
    def self.valid_id?(id : String) : Bool
      return false if id.empty? || id.bytesize > 1024

      id.split('/').all? { |segment| segment.matches?(/\A[A-Za-z0-9_\-][A-Za-z0-9_.\-]*\z/) }
    end
  end
end
