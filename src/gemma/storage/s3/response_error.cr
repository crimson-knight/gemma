require "../../error"

class Gemma
  module Storage
    class S3 < Storage::Base
      # Raised when an S3-compatible service answers with a status outside
      # 2xx. It carries the status code and the raw response body (S3 error
      # bodies are short XML documents), which is enough to diagnose the
      # failure without parsing XML.
      class ResponseError < Gemma::Error
        getter http_method : String
        getter resource : String
        getter status_code : Int32
        getter response_body : String

        def initialize(@http_method : String, @resource : String, @status_code : Int32, @response_body : String)
          body_text = @response_body.empty? ? "(empty body)" : @response_body
          super("S3 #{@http_method} #{@resource} failed with HTTP #{@status_code}: #{body_text}")
        end
      end
    end
  end
end
