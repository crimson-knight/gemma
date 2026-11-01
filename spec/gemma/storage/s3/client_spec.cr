require "../../../spec_helper"

Spectator.describe Gemma::Storage::S3::Client do
  let(signed_at) { Time.utc(2013, 5, 24) }

  # Recomputes a SigV4 signature from an expected canonical request, without
  # going through `SignatureV4`, so the spec checks the client's canonical
  # request and host header independently.
  def expected_signature(canonical_request : String, secret_key : String, region : String, signed_at : Time) : String
    date = signed_at.to_s("%Y%m%d")
    string_to_sign = "AWS4-HMAC-SHA256\n#{signed_at.to_s("%Y%m%dT%H%M%SZ")}\n" \
                     "#{date}/#{region}/s3/aws4_request\n#{Digest::SHA256.hexdigest(canonical_request)}"
    key = OpenSSL::HMAC.digest(:sha256, "AWS4#{secret_key}", date)
    key = OpenSSL::HMAC.digest(:sha256, key, region)
    key = OpenSSL::HMAC.digest(:sha256, key, "s3")
    key = OpenSSL::HMAC.digest(:sha256, key, "aws4_request")
    OpenSSL::HMAC.hexdigest(:sha256, key, string_to_sign)
  end

  describe "addressing styles" do
    it "defaults to virtual-hosted on AWS" do
      client = described_class.new("us-east-2", "key", "secret")
      request, _signature = client.sign_request("GET", "examplebucket", "photos/a.jpg", HTTP::Headers.new, nil, signed_at)

      expect(client.addressing_style).to eq(Gemma::Storage::S3::AddressingStyle::VirtualHosted)
      expect(request.headers["Host"]).to eq("examplebucket.s3.us-east-2.amazonaws.com")
      expect(request.resource).to eq("/photos/a.jpg")
    end

    it "uses path-style on AWS when asked" do
      client = described_class.new("us-east-2", "key", "secret", addressing_style: :path)
      request, signature = client.sign_request("GET", "examplebucket", "photos/a.jpg", HTTP::Headers.new, nil, signed_at)

      expect(request.headers["Host"]).to eq("s3.us-east-2.amazonaws.com")
      expect(request.resource).to eq("/examplebucket/photos/a.jpg")
      expect(signature.canonical_request.lines[1]).to eq("/examplebucket/photos/a.jpg")
      expect(client.presigned_url("examplebucket", "photos/a.jpg", signed_at: signed_at)).to start_with(
        "https://s3.us-east-2.amazonaws.com/examplebucket/photos/a.jpg?")
    end

    it "defaults to virtual-hosted for DigitalOcean Spaces" do
      client = described_class.new("nyc3", "key", "secret", endpoint: "https://nyc3.digitaloceanspaces.com")
      expect(client.addressing_style).to eq(Gemma::Storage::S3::AddressingStyle::VirtualHosted)
    end

    it "defaults to path-style for other endpoints and signs the port in Host" do
      client = described_class.new("us-east-1", "key", "secret", endpoint: "http://localhost:9000")
      request, signature = client.sign_request("PUT", "gemma", "a.txt", HTTP::Headers.new, "hi".to_slice, signed_at)

      expect(client.addressing_style).to eq(Gemma::Storage::S3::AddressingStyle::Path)
      expect(request.headers["Host"]).to eq("localhost:9000")
      expect(request.resource).to eq("/gemma/a.txt")
      expect(signature.canonical_request).to contain("host:localhost:9000\n")
    end

    it "rejects an endpoint without a scheme" do
      expect { described_class.new("nyc3", "key", "secret", endpoint: "nyc3.digitaloceanspaces.com") }.to raise_error(ArgumentError)
    end
  end

  describe "#presigned_url" do
    it "reproduces the S3 documentation example with a virtual-hosted client" do
      client = described_class.new("us-east-1", "AKIAIOSFODNN7EXAMPLE", "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
        endpoint: "https://s3.amazonaws.com", addressing_style: :virtual_hosted)

      expect(client.presigned_url("examplebucket", "test.txt", expires_in: 86_400.seconds, signed_at: signed_at)).to eq(
        "https://examplebucket.s3.amazonaws.com/test.txt?X-Amz-Algorithm=AWS4-HMAC-SHA256" \
        "&X-Amz-Credential=AKIAIOSFODNN7EXAMPLE%2F20130524%2Fus-east-1%2Fs3%2Faws4_request" \
        "&X-Amz-Date=20130524T000000Z&X-Amz-Expires=86400&X-Amz-SignedHeaders=host" \
        "&X-Amz-Signature=aeeed9bbccd4d02ee5c0109b86d86835f995330da4c265957d157751f604d404")
    end

    it "signs a DigitalOcean Spaces URL for the bucket subdomain (the HappyCoach patch)" do
      secret = "spaces-secret" # secret-scan-gate:allow (fixture, not a credential)
      client = described_class.new("nyc3", "DO00EXAMPLE", secret, endpoint: "https://nyc3.digitaloceanspaces.com")
      url = client.presigned_url("happycoachai", "production/a b.jpg", expires_in: 1.hour, signed_at: signed_at)

      query = "X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=DO00EXAMPLE%2F20130524%2Fnyc3%2Fs3%2Faws4_request" \
              "&X-Amz-Date=20130524T000000Z&X-Amz-Expires=3600&X-Amz-SignedHeaders=host"
      canonical_request = "GET\n/production/a%20b.jpg\n#{query}\n" \
                          "host:happycoachai.nyc3.digitaloceanspaces.com\n\nhost\nUNSIGNED-PAYLOAD"

      expect(url).to eq(
        "https://happycoachai.nyc3.digitaloceanspaces.com/production/a%20b.jpg?#{query}" \
        "&X-Amz-Signature=#{expected_signature(canonical_request, secret, "nyc3", signed_at)}")
    end
  end

  describe "#inspect" do
    it "leaves the secret key out" do
      client = described_class.new("nyc3", "key", "very-secret")
      expect(client.inspect).not_to contain("very-secret")
    end
  end
end
