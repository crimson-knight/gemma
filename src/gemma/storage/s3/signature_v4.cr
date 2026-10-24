require "digest/sha256"
require "http/headers"
require "openssl/hmac"

module Gemma
  module Storage
    class S3 < Storage::Base
      # Signs requests with AWS Signature Version 4 (`AWS4-HMAC-SHA256`).
      #
      # The signer is service-neutral so it can be checked against AWS's
      # published `aws-sig-v4-test-suite`; `Gemma::Storage::S3::Client` uses it
      # with the `s3` service, both for the `Authorization` header and for
      # presigned (query-string) URLs.
      #
      # Paths are taken as already URI-encoded (S3 rule: each key byte encoded
      # once, no path normalization). Query keys and values are taken raw and
      # encoded here.
      #
      # ```
      # signer = Gemma::Storage::S3::SignatureV4.new(
      #   aws_access_key: "AKIDEXAMPLE",
      #   aws_secret_key: "secret",
      #   region: "us-east-1",
      # )
      # headers = HTTP::Headers{"Host" => "examplebucket.s3.amazonaws.com"}
      # signature = signer.sign("GET", "/test.txt", [] of {String, String}, headers,
      #   Gemma::Storage::S3::SignatureV4::EMPTY_PAYLOAD_HASH, Time.utc)
      # signature.authorization_header # => "AWS4-HMAC-SHA256 Credential=..."
      # ```
      struct SignatureV4
        ALGORITHM          = "AWS4-HMAC-SHA256"
        EMPTY_PAYLOAD_HASH = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        UNSIGNED_PAYLOAD   = "UNSIGNED-PAYLOAD"
        LONG_DATE_FORMAT   = "%Y%m%dT%H%M%SZ"
        SHORT_DATE_FORMAT  = "%Y%m%d"

        # The parts of one signing pass. `canonical_request` and
        # `string_to_sign` are kept so specs can compare them with the
        # published test vectors.
        record Signature,
          aws_access_key : String,
          credential_scope : String,
          canonical_request : String,
          string_to_sign : String,
          signed_header_names : String,
          hex_signature : String do
          # Returns the value for the `Authorization` request header.
          def authorization_header : String
            "#{ALGORITHM} Credential=#{aws_access_key}/#{credential_scope}, " \
            "SignedHeaders=#{signed_header_names}, Signature=#{hex_signature}"
          end
        end

        getter aws_access_key : String
        getter region : String
        getter service : String

        def initialize(@aws_access_key : String, @aws_secret_key : String, @region : String, @service : String = "s3")
        end

        # Hides the secret key from `inspect` output, which can reach logs.
        def inspect(io : IO) : Nil
          io << "#<" << self.class << " aws_access_key=" << @aws_access_key.inspect
          io << " region=" << @region.inspect << " service=" << @service.inspect << '>'
        end

        # Signs a request whose credentials travel in the `Authorization`
        # header. *headers* must already contain every header to sign,
        # including `Host` and `X-Amz-Date` (see `.long_date`).
        def sign(
          method : String,
          encoded_path : String,
          query_parameters : Array({String, String}),
          headers : HTTP::Headers,
          payload_hash : String,
          signed_at : Time,
        ) : Signature
          canonical_header_lines, signed_header_names = canonical_headers(headers)
          canonical_request = String.build do |io|
            io << method << '\n'
            io << encoded_path << '\n'
            io << canonical_query(query_parameters) << '\n'
            io << canonical_header_lines << '\n'
            io << signed_header_names << '\n'
            io << payload_hash
          end

          scope = credential_scope(signed_at)
          string_to_sign = String.build do |io|
            io << ALGORITHM << '\n'
            io << self.class.long_date(signed_at) << '\n'
            io << scope << '\n'
            io << Digest::SHA256.hexdigest(canonical_request)
          end

          hex_signature = OpenSSL::HMAC.hexdigest(:sha256, signing_key(signed_at), string_to_sign)
          Signature.new(@aws_access_key, scope, canonical_request, string_to_sign, signed_header_names, hex_signature)
        end

        # Builds the query parameters of a presigned URL (SigV4 query-string
        # authentication). Only the `host` header is signed and the payload is
        # `UNSIGNED-PAYLOAD`, as S3 expects for presigned URLs.
        #
        # Returns the full, encoded query string including `X-Amz-Signature`,
        # together with the `Signature` it came from.
        def presign(
          method : String,
          encoded_path : String,
          host : String,
          expires_in : Time::Span,
          signed_at : Time,
          extra_query_parameters : Array({String, String}) = [] of {String, String},
        ) : {String, Signature}
          query_parameters = extra_query_parameters + [
            {"X-Amz-Algorithm", ALGORITHM},
            {"X-Amz-Credential", "#{@aws_access_key}/#{credential_scope(signed_at)}"},
            {"X-Amz-Date", self.class.long_date(signed_at)},
            {"X-Amz-Expires", expires_in.total_seconds.to_i64.to_s},
            {"X-Amz-SignedHeaders", "host"},
          ]
          headers = HTTP::Headers{"Host" => host}
          signature = sign(method, encoded_path, query_parameters, headers, UNSIGNED_PAYLOAD, signed_at)

          query_string = "#{canonical_query(query_parameters)}&X-Amz-Signature=#{signature.hex_signature}"
          {query_string, signature}
        end

        # Formats *time* as the `X-Amz-Date` value (`20150830T123600Z`).
        def self.long_date(time : Time) : String
          time.to_utc.to_s(LONG_DATE_FORMAT)
        end

        # Percent-encodes *text* the way SigV4 requires: every byte except the
        # unreserved characters `A-Z a-z 0-9 - . _ ~` becomes `%XX` (uppercase
        # hex). Pass `keep_slashes: true` to encode an S3 object key as a path.
        def self.uri_encode(text : String, keep_slashes : Bool = false) : String
          String.build do |io|
            text.each_byte do |byte|
              if URI.unreserved?(byte) || (keep_slashes && byte == '/'.ord)
                io.write_byte(byte)
              else
                io << '%'
                io << byte.to_s(16, upcase: true).rjust(2, '0')
              end
            end
          end
        end

        private def credential_scope(signed_at : Time) : String
          "#{signed_at.to_utc.to_s(SHORT_DATE_FORMAT)}/#{@region}/#{@service}/aws4_request"
        end

        private def canonical_query(query_parameters : Array({String, String})) : String
          encoded_pairs = query_parameters.map do |(key, value)|
            {self.class.uri_encode(key), self.class.uri_encode(value)}
          end
          encoded_pairs.sort!.map { |(key, value)| "#{key}=#{value}" }.join('&')
        end

        # Returns the canonical header block and the `;`-joined signed header
        # names. Names are lowercased and sorted; values are trimmed, inner
        # runs of spaces collapse to one, and repeated headers join with `,`.
        private def canonical_headers(headers : HTTP::Headers) : {String, String}
          values_by_name = Hash(String, Array(String)).new
          headers.each do |name, values|
            list_of_values = values_by_name[name.downcase] ||= [] of String
            values.each { |value| list_of_values << value.strip.gsub(/\s+/, " ") }
          end

          sorted_names = values_by_name.keys.sort!
          header_block = String.build do |io|
            sorted_names.each do |name|
              io << name << ':' << values_by_name[name].join(',') << '\n'
            end
          end
          {header_block, sorted_names.join(';')}
        end

        private def signing_key(signed_at : Time) : Bytes
          date_key = OpenSSL::HMAC.digest(:sha256, "AWS4#{@aws_secret_key}", signed_at.to_utc.to_s(SHORT_DATE_FORMAT))
          region_key = OpenSSL::HMAC.digest(:sha256, date_key, @region)
          service_key = OpenSSL::HMAC.digest(:sha256, region_key, @service)
          OpenSSL::HMAC.digest(:sha256, service_key, "aws4_request")
        end
      end
    end
  end
end
