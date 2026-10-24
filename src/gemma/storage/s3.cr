require "./base"
require "../content_disposition"
require "./s3/*"

class Gemma
  module Storage
    # Stores files in an S3-compatible bucket: AWS S3, DigitalOcean Spaces,
    # MinIO. It talks to the service through `Gemma::Storage::S3::Client`,
    # which signs requests with AWS Signature Version 4 and needs no XML
    # library.
    #
    # ```
    # client = Gemma::Storage::S3::Client.new("nyc3", "key", "secret",
    #   endpoint: "https://nyc3.digitaloceanspaces.com")
    # storage = Gemma::Storage::S3.new(bucket: "my-bucket", client: client, prefix: "uploads")
    # ```
    class S3 < Storage::Base
      DEFAULT_URL_EXPIRY = 1.day

      getter bucket : String
      getter client : Client
      getter? public : Bool

      # Initializes a storage for uploading to S3.
      #
      # :bucket
      # : (Required). Name of the S3 bucket.
      #
      # :client
      # : (Required). A `Gemma::Storage::S3::Client` holding the region,
      #   credentials, endpoint and addressing style.
      #
      # :prefix
      # : "Directory" inside the bucket to store files into.
      #
      # :upload_options
      # : Additional headers sent with every upload, e.g. `{"x-amz-acl" => "private"}`.
      #
      # :public
      # : Sets public access (`x-amz-acl: public-read`) on every uploaded file.
      #
      def initialize(
        @bucket : String,
        @client : Client,
        @prefix : String? = nil,
        @upload_options : Hash(String, String) = Hash(String, String).new,
        @public : Bool = false,
      )
      end

      # Copies the file into the given location.
      #
      def upload(io : IO | UploadedFile, id : String, move = false, **upload_options)
        headers = Hash(String, String).new
        if (metadata = upload_options[:metadata]?) && metadata.is_a?(Gemma::UploadedFile::MetadataType)
          if filename = metadata["filename"]?
            headers["Content-Disposition"] = ContentDisposition.inline(filename.to_s)
          end
        end
        headers["x-amz-acl"] = "public-read" if public?

        headers.merge!(@upload_options)
        upload_options.each do |option_name, value|
          next if option_name == :metadata
          headers[option_name.to_s] = value.to_s
        end

        source = io.is_a?(UploadedFile) ? io.io : io
        body = IO::Memory.new
        IO.copy(source, body)
        client.put_object(bucket, object_key(id), body.to_slice, headers)

        true
      end

      def upload(io : IO | UploadedFile, id : String, metadata : Gemma::UploadedFile::MetadataType, move = false, **upload_options)
        upload(io, id, move, **(upload_options.merge(metadata: metadata)))
      end

      # Returns an IO holding the whole object, rewound to position 0. The
      # HTTP connection is already closed, so the IO stays readable.
      # Raises `Gemma::FileNotFound` when the object does not exist.
      def open(id : String, **options) : IO
        io = IO::Memory.new
        client.get_object(bucket, object_key(id)) do |response|
          if body_io = response.body_io?
            IO.copy(body_io, io)
          else
            io << response.body
          end
        end
        io.rewind
      rescue error : ResponseError
        raise error unless error.status_code == 404
        raise Gemma::FileNotFound.new("file #{id.inspect} not found on storage: #{error.message}", cause: error)
      end

      # Returns a presigned GET URL to the file. Pass `expires_in:` (a
      # `Time::Span` or a number of seconds) to change the default of one day.
      def url(id : String, **options) : String
        client.presigned_url(bucket, object_key(id), expires_in: url_expiry(options[:expires_in]?))
      end

      # Returns true if the file exists on S3. S3 answers 403 instead of 404
      # for a missing object when the credentials may not list the bucket, so
      # both mean "does not exist"; any other failure raises `ResponseError`.
      def exists?(id : String) : Bool
        client.head_object(bucket, object_key(id))
        true
      rescue error : ResponseError
        raise error unless {403, 404}.includes?(error.status_code)
        false
      end

      # Deletes the file.
      def delete(id : String) : Bool
        client.delete_object(bucket, object_key(id))
      end

      def clean(path)
      end

      def path(id : String)
        object_key(id)
      end

      # Returns object key with potential prefix.
      def object_key(id : String) : String
        @prefix ? [@prefix, id].join("/") : id
      end

      private def url_expiry(requested_expiry) : Time::Span
        if requested_expiry.is_a?(Time::Span)
          requested_expiry
        elsif requested_expiry.is_a?(Int)
          requested_expiry.seconds
        else
          DEFAULT_URL_EXPIRY
        end
      end
    end
  end
end
