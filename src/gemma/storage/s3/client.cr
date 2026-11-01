require "http/client"
require "uri"
require "./addressing_style"
require "./response_error"
require "./signature_v4"

module Gemma
  module Storage
    class S3 < Storage::Base
      # A small S3 client that covers what `Gemma::Storage::S3` needs:
      # put, get, head and delete of single objects, plus presigned GET URLs.
      # Requests are signed with `SignatureV4`; responses are never parsed as
      # XML. A failed request raises `ResponseError` with the status code and
      # the raw body.
      #
      # ```
      # # AWS
      # client = Gemma::Storage::S3::Client.new("us-east-2", "key", "secret")
      #
      # # DigitalOcean Spaces (virtual-hosted URLs by default)
      # client = Gemma::Storage::S3::Client.new("nyc3", "key", "secret",
      #   endpoint: "https://nyc3.digitaloceanspaces.com")
      #
      # # MinIO or another local endpoint (path-style URLs by default)
      # client = Gemma::Storage::S3::Client.new("us-east-1", "key", "secret",
      #   endpoint: "http://localhost:9000")
      # ```
      #
      # Each request opens its own `HTTP::Client`, so one `Client` is safe to
      # share across fibers.
      class Client
        CONNECT_TIMEOUT        = 10.seconds
        READ_TIMEOUT           = 60.seconds
        ERROR_BODY_LIMIT_BYTES = 65_536
        SPACES_HOST_SUFFIX     = ".digitaloceanspaces.com"

        # Where a request goes: the host (with a non-default port) and the
        # URI-encoded path.
        private record RequestTarget, host_header : String, connect_host : String, encoded_path : String

        getter region : String
        getter aws_access_key : String
        getter endpoint : URI
        getter addressing_style : AddressingStyle

        # Creates a client for *region*.
        #
        # *endpoint* defaults to AWS (`https://s3.<region>.amazonaws.com`).
        # *addressing_style* defaults to `AddressingStyle::VirtualHosted` for
        # AWS and DigitalOcean Spaces, and to `AddressingStyle::Path` for any
        # other endpoint (MinIO, Ceph, a local test server).
        def initialize(
          @region : String,
          @aws_access_key : String,
          aws_secret_key : String,
          endpoint : String? = nil,
          addressing_style : AddressingStyle? = nil,
        )
          @signer = SignatureV4.new(@aws_access_key, aws_secret_key, @region)
          @endpoint = endpoint ? self.class.parse_endpoint(endpoint) : URI.parse("https://s3.#{@region}.amazonaws.com")
          @addressing_style = addressing_style || self.class.default_addressing_style(endpoint, @endpoint)
        end

        # Hides the secret key from `inspect` output, which can reach logs.
        def inspect(io : IO) : Nil
          io << "#<" << self.class << " region=" << @region.inspect
          io << " endpoint=" << @endpoint.to_s.inspect << " addressing_style=" << @addressing_style << '>'
        end

        # Uploads *body* as the object *key*. *headers* are sent and signed
        # as given (e.g. `Content-Type`, `Content-Disposition`, `x-amz-acl`).
        # Returns the response headers (`ETag` and friends).
        def put_object(bucket : String, key : String, body : Bytes, headers : Hash(String, String) = Hash(String, String).new) : HTTP::Headers
          request_headers = HTTP::Headers.new
          headers.each { |header_name, value| request_headers[header_name] = value }

          perform("PUT", bucket, key, request_headers, body) do |response|
            response.headers
          end
        end

        # Streams the object *key*: yields the successful response, whose
        # `body_io` holds the object bytes. The connection closes when the
        # block returns, so copy the body inside the block.
        def get_object(bucket : String, key : String, & : HTTP::Client::Response -> T) : T forall T
          perform("GET", bucket, key, HTTP::Headers.new, nil) do |response|
            yield response
          end
        end

        # Returns the headers of the object *key*. A missing object raises
        # `ResponseError` with status 404 (403 when the credentials may not
        # list the bucket).
        def head_object(bucket : String, key : String) : HTTP::Headers
          perform("HEAD", bucket, key, HTTP::Headers.new, nil) do |response|
            response.headers
          end
        end

        # Deletes the object *key*. S3 answers 204 whether or not the object
        # existed; returns true for any 2xx answer.
        def delete_object(bucket : String, key : String) : Bool
          perform("DELETE", bucket, key, HTTP::Headers.new, nil) do |response|
            response.success?
          end
        end

        # Returns a presigned URL for *key* (SigV4 query-string
        # authentication), valid for *expires_in*. The URL uses this client's
        # addressing style, so a Spaces URL reads
        # `https://<bucket>.<region>.digitaloceanspaces.com/<key>?X-Amz-...`.
        def presigned_url(
          bucket : String,
          key : String,
          expires_in : Time::Span = 1.day,
          http_method : String = "GET",
          signed_at : Time = Time.utc,
        ) : String
          target = request_target(bucket, key)
          query_string, _signature = @signer.presign(http_method, target.encoded_path, target.host_header, expires_in, signed_at)
          "#{@endpoint.scheme}://#{target.host_header}#{target.encoded_path}?#{query_string}"
        end

        # Signs a request without sending it. `put_object` and the other
        # operations use it; specs use it to inspect the canonical request.
        def sign_request(
          http_method : String,
          bucket : String,
          key : String,
          headers : HTTP::Headers,
          body : Bytes?,
          signed_at : Time = Time.utc,
        ) : {HTTP::Request, SignatureV4::Signature}
          target = request_target(bucket, key)
          payload_hash = body ? Digest::SHA256.hexdigest(body) : SignatureV4::EMPTY_PAYLOAD_HASH
          headers["Host"] = target.host_header
          headers["X-Amz-Date"] = SignatureV4.long_date(signed_at)
          headers["X-Amz-Content-Sha256"] = payload_hash

          signature = @signer.sign(http_method, target.encoded_path, [] of {String, String}, headers, payload_hash, signed_at)
          headers["Authorization"] = signature.authorization_header
          {HTTP::Request.new(http_method, target.encoded_path, headers, body), signature}
        end

        # :nodoc:
        def self.parse_endpoint(endpoint : String) : URI
          uri = URI.parse(endpoint)
          unless uri.host.presence && {"http", "https"}.includes?(uri.scheme)
            raise ArgumentError.new("S3 endpoint must be an absolute http(s) URL, got #{endpoint.inspect}")
          end
          uri
        end

        # :nodoc:
        def self.default_addressing_style(endpoint_option : String?, endpoint : URI) : AddressingStyle
          return AddressingStyle::VirtualHosted if endpoint_option.nil?
          return AddressingStyle::VirtualHosted if endpoint.host.to_s.ends_with?(SPACES_HOST_SUFFIX)
          AddressingStyle::Path
        end

        private def perform(
          http_method : String,
          bucket : String,
          key : String,
          headers : HTTP::Headers,
          body : Bytes?,
          & : HTTP::Client::Response -> T
        ) : T forall T
          request, _signature = sign_request(http_method, bucket, key, headers, body)
          connect_host = request_target(bucket, key).connect_host

          http_client = HTTP::Client.new(connect_host, @endpoint.port, tls: @endpoint.scheme == "https")
          # Object bytes must arrive exactly as stored, so a gzip object is
          # never decoded on the way through.
          http_client.compress = false
          http_client.connect_timeout = CONNECT_TIMEOUT
          http_client.read_timeout = READ_TIMEOUT
          begin
            http_client.exec(request) do |response|
              raise_unless_successful(http_method, request.resource, response)
              yield response
            end
          ensure
            http_client.close
          end
        end

        private def raise_unless_successful(http_method : String, resource : String, response : HTTP::Client::Response) : Nil
          return if response.success?

          response_body = String.build do |io|
            if body_io = response.body_io?
              IO.copy(body_io, io, ERROR_BODY_LIMIT_BYTES)
            else
              io << response.body?.to_s[0, ERROR_BODY_LIMIT_BYTES]
            end
          end
          raise ResponseError.new(http_method, resource, response.status_code, response_body.strip)
        end

        private def request_target(bucket : String, key : String) : RequestTarget
          endpoint_host = @endpoint.host.to_s
          base_path = @endpoint.path.rstrip('/')
          encoded_key = SignatureV4.uri_encode(key, keep_slashes: true)

          if @addressing_style.virtual_hosted?
            connect_host = "#{bucket}.#{endpoint_host}"
            RequestTarget.new(with_port(connect_host), connect_host, "#{base_path}/#{encoded_key}")
          else
            RequestTarget.new(with_port(endpoint_host), endpoint_host, "#{base_path}/#{SignatureV4.uri_encode(bucket)}/#{encoded_key}")
          end
        end

        # Appends the endpoint's port when it is not the scheme's default,
        # because SigV4 signs the `Host` header exactly as sent.
        private def with_port(host : String) : String
          port = @endpoint.port
          return host if port.nil? || port == URI.default_port(@endpoint.scheme.to_s)
          "#{host}:#{port}"
        end
      end
    end
  end
end
