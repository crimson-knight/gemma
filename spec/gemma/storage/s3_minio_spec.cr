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
  Spectator.describe "Gemma::Storage::S3 against #{ENV["GEMMA_S3_TEST_ENDPOINT"]?}" do
    let(endpoint) { ENV["GEMMA_S3_TEST_ENDPOINT"] }
    let(access_key) { ENV["GEMMA_S3_TEST_ACCESS_KEY"] }
    let(secret_key) { ENV["GEMMA_S3_TEST_SECRET_KEY"] }
    let(region) { "us-east-1" }
    let(bucket) { "gemma-spec-#{Random::Secure.hex(4)}" }
    let(client) { Gemma::Storage::S3::Client.new(region, access_key, secret_key, endpoint: endpoint) }
    let(storage) { Gemma::Storage::S3.new(bucket: bucket, client: client, prefix: "uploads") }

    # Bucket creation is outside the storage's five operations, so the spec
    # signs that one request itself.
    def create_bucket(endpoint : String, region : String, access_key : String, secret_key : String, bucket : String) : Nil
      uri = URI.parse(endpoint)
      host_header = uri.port ? "#{uri.host}:#{uri.port}" : uri.host.to_s
      signed_at = Time.utc
      headers = HTTP::Headers{
        "Host"                 => host_header,
        "X-Amz-Date"           => Gemma::Storage::S3::SignatureV4.long_date(signed_at),
        "X-Amz-Content-Sha256" => Gemma::Storage::S3::SignatureV4::EMPTY_PAYLOAD_HASH,
      }
      signer = Gemma::Storage::S3::SignatureV4.new(access_key, secret_key, region)
      signature = signer.sign("PUT", "/#{bucket}", [] of {String, String}, headers,
        Gemma::Storage::S3::SignatureV4::EMPTY_PAYLOAD_HASH, signed_at)
      headers["Authorization"] = signature.authorization_header
      response = HTTP::Client.new(uri).exec(HTTP::Request.new("PUT", "/#{bucket}", headers))
      raise "bucket creation failed: #{response.status_code} #{response.body}" unless response.success?
    end

    before_each do
      WebMock.allow_net_connect = true
      create_bucket(endpoint, region, access_key, secret_key, bucket)
    end

    after_each { WebMock.allow_net_connect = false }

    it "uploads, checks, reads, presigns and deletes an object" do
      content = "binary\u0000payload ✓ #{Random::Secure.hex(8)}"
      metadata = Gemma::UploadedFile::MetadataType{"filename" => "résumé photo.jpg"}
      id = "nested dir/résumé photo.jpg"

      expect(storage.exists?(id)).to be_false
      expect(storage.upload(IO::Memory.new(content), id, metadata)).to be_true
      expect(storage.exists?(id)).to be_true

      io = storage.open(id)
      expect(io.pos).to eq(0)
      expect(io.gets_to_end).to eq(content)

      presigned_uri = URI.parse(storage.url(id, expires_in: 5.minutes))
      presigned = HTTP::Client.new(presigned_uri).get(presigned_uri.request_target)
      expect(presigned.status_code).to eq(200)
      expect(presigned.body).to eq(content)
      expect(presigned.headers["Content-Disposition"]).to eq(Gemma::ContentDisposition.inline("résumé photo.jpg"))

      expect(storage.delete(id)).to be_true
      expect(storage.exists?(id)).to be_false
      expect { storage.open(id) }.to raise_error(Gemma::FileNotFound)
    end

    it "reports a bad signature with the status code and the raw body" do
      wrong_client = Gemma::Storage::S3::Client.new(region, access_key, "wrong-secret", endpoint: endpoint)
      wrong_storage = Gemma::Storage::S3.new(bucket: bucket, client: wrong_client)

      expect { wrong_storage.upload(IO::Memory.new("x"), "denied.txt") }.to raise_error(
        Gemma::Storage::S3::ResponseError, /HTTP 403: .*SignatureDoesNotMatch/m)
    end
  end
{% end %}
