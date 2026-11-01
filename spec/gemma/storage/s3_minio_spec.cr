require "../../spec_helper"

# Round-trips against a real S3-compatible server. Compiled only when
# GEMMA_S3_TEST_ENDPOINT is set, e.g. for a local MinIO container:
#
#   docker run -d --name gemma-minio -p 9000:9000 \
#     -e MINIO_ROOT_USER=gemma-spec -e MINIO_ROOT_PASSWORD=gemma-spec-secret \
#     cgr.dev/chainguard/minio@sha256:73297936408b731668ca0e835ac9add1a35cb6026a125c2f0cd476d9ef48222c \
#     server /data
#   GEMMA_S3_TEST_ENDPOINT=http://localhost:9000 GEMMA_S3_TEST_ACCESS_KEY=gemma-spec \
#     GEMMA_S3_TEST_SECRET_KEY=gemma-spec-secret crystal-alpha spec spec/gemma/storage/s3_minio_spec.cr
{% if env("GEMMA_S3_TEST_ENDPOINT") %}
  private MINIO_REGION = "us-east-1"

  # The connection settings for the server under test, read once from the
  # environment the spec run was started with.
  private record MinioSettings, endpoint : String, access_key : String, secret_key : String do
    def self.from_environment : MinioSettings
      new(
        ENV["GEMMA_S3_TEST_ENDPOINT"]? || raise("GEMMA_S3_TEST_ENDPOINT is not set"),
        ENV["GEMMA_S3_TEST_ACCESS_KEY"]? || raise("GEMMA_S3_TEST_ACCESS_KEY is not set"),
        ENV["GEMMA_S3_TEST_SECRET_KEY"]? || raise("GEMMA_S3_TEST_SECRET_KEY is not set"),
      )
    end
  end

  # Bucket creation is outside the storage's five operations, so the spec
  # signs that one request itself.
  private def create_bucket(settings : MinioSettings, bucket : String) : Nil
    uri = URI.parse(settings.endpoint)
    host_header = uri.port ? "#{uri.host}:#{uri.port}" : uri.host.to_s
    signed_at = Time.utc
    headers = HTTP::Headers{
      "Host"                 => host_header,
      "X-Amz-Date"           => Gemma::Storage::S3::SignatureV4.long_date(signed_at),
      "X-Amz-Content-Sha256" => Gemma::Storage::S3::SignatureV4::EMPTY_PAYLOAD_HASH,
    }
    signer = Gemma::Storage::S3::SignatureV4.new(settings.access_key, settings.secret_key, MINIO_REGION)
    signature = signer.sign("PUT", "/#{bucket}", [] of {String, String}, headers,
      Gemma::Storage::S3::SignatureV4::EMPTY_PAYLOAD_HASH, signed_at)
    headers["Authorization"] = signature.authorization_header
    response = HTTP::Client.new(uri).exec(HTTP::Request.new("PUT", "/#{bucket}", headers))
    raise "bucket creation failed: #{response.status_code} #{response.body}" unless response.success?
  end

  # Yields a storage on a new bucket, with real network access allowed.
  private def with_minio_storage(&)
    settings = MinioSettings.from_environment
    bucket = "gemma-spec-#{Random::Secure.hex(4)}"
    WebMock.allow_net_connect = true
    begin
      create_bucket(settings, bucket)
      client = Gemma::Storage::S3::Client.new(MINIO_REGION, settings.access_key, settings.secret_key, endpoint: settings.endpoint)
      yield settings, bucket, Gemma::Storage::S3.new(bucket: bucket, client: client, prefix: "uploads")
    ensure
      WebMock.allow_net_connect = false
    end
  end

  describe "Gemma::Storage::S3 against #{ENV["GEMMA_S3_TEST_ENDPOINT"]?}" do
    it "uploads, checks, reads, presigns and deletes an object" do
      with_minio_storage do |_settings, _bucket, storage|
        content = "binary\u0000payload ✓ #{Random::Secure.hex(8)}"
        metadata = Gemma::UploadedFile::MetadataType{"filename" => "résumé photo.jpg"}
        id = "nested dir/résumé photo.jpg"

        storage.exists?(id).should be_false
        storage.upload(IO::Memory.new(content), id, metadata)
        storage.exists?(id).should be_true

        io = storage.open(id)
        io.pos.should eq(0)
        io.gets_to_end.should eq(content)

        presigned_uri = URI.parse(storage.url(id, expires_in: 5.minutes))
        presigned = HTTP::Client.new(presigned_uri).get(presigned_uri.request_target)
        presigned.status_code.should eq(200)
        presigned.body.should eq(content)
        presigned.headers["Content-Disposition"].should eq(Gemma::ContentDisposition.inline("résumé photo.jpg"))

        storage.delete(id)
        storage.exists?(id).should be_false
        expect_raises(Gemma::FileNotFound) { storage.open(id) }
      end
    end

    it "reports a bad signature with the status code and the raw body" do
      with_minio_storage do |settings, bucket, _storage|
        wrong_client = Gemma::Storage::S3::Client.new(MINIO_REGION, settings.access_key, "wrong-secret", endpoint: settings.endpoint)
        wrong_storage = Gemma::Storage::S3.new(bucket: bucket, client: wrong_client)

        expect_raises(Gemma::Storage::S3::ResponseError, /HTTP 403: .*SignatureDoesNotMatch/m) do
          wrong_storage.upload(IO::Memory.new("x"), "denied.txt")
        end
      end
    end
  end
{% end %}
