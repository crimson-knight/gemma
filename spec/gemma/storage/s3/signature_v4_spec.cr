require "../../../spec_helper"

# Vectors from AWS's aws-sig-v4-test-suite, read from the copy vendored by
# mhart/aws4 at commit 9d00a5acf4df38ec80f6918fa7f17fc06492e01f
# (test/aws-sig-v4-test-suite/<case>/<case>.{req,creq,authz}).
private TEST_SUITE_ACCESS_KEY = "AKIDEXAMPLE"                              # secret-scan-gate:allow (AWS published example key)
private TEST_SUITE_SECRET_KEY = "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY" # secret-scan-gate:allow (AWS published example key)
private TEST_SUITE_TIME       = Time.utc(2015, 8, 30, 12, 36, 0)

# Vectors from the Amazon S3 API Reference, "Signature Calculations for the
# Authorization Header: Transferring Payload in a Single Chunk" and
# "Authenticating Requests: Using Query Parameters". The same values are
# asserted by s3s-project/s3s (crates/s3s-sigv4/src/methods.rs) and
# apache/arrow-rs-object-store (src/aws/credential.rs).
private S3_DOCS_ACCESS_KEY = "AKIAIOSFODNN7EXAMPLE"                     # secret-scan-gate:allow (AWS published example key)
private S3_DOCS_SECRET_KEY = "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY" # secret-scan-gate:allow (AWS published example key)
private S3_DOCS_TIME       = Time.utc(2013, 5, 24)

private EMPTY_HASH = Gemma::Storage::S3::SignatureV4::EMPTY_PAYLOAD_HASH

Spectator.describe Gemma::Storage::S3::SignatureV4 do
  def test_suite_signer
    Gemma::Storage::S3::SignatureV4.new(TEST_SUITE_ACCESS_KEY, TEST_SUITE_SECRET_KEY, "us-east-1", "service")
  end

  def test_suite_headers(extra_headers : Array({String, String}) = [] of {String, String}) : HTTP::Headers
    headers = HTTP::Headers.new
    headers.add("Host", "example.amazonaws.com")
    extra_headers.each { |(header_name, value)| headers.add(header_name, value) }
    headers.add("X-Amz-Date", "20150830T123600Z")
    headers
  end

  def test_suite_authorization(signed_headers : String, hex_signature : String) : String
    "AWS4-HMAC-SHA256 Credential=AKIDEXAMPLE/20150830/us-east-1/service/aws4_request, " \
    "SignedHeaders=#{signed_headers}, Signature=#{hex_signature}"
  end

  def no_query
    [] of {String, String}
  end

  describe "#sign with the aws-sig-v4-test-suite" do
    it "signs get-vanilla" do
      signature = test_suite_signer.sign("GET", "/", no_query, test_suite_headers, EMPTY_HASH, TEST_SUITE_TIME)

      expect(signature.canonical_request).to eq(
        "GET\n/\n\nhost:example.amazonaws.com\nx-amz-date:20150830T123600Z\n\nhost;x-amz-date\n#{EMPTY_HASH}")
      expect(signature.string_to_sign).to eq(
        "AWS4-HMAC-SHA256\n20150830T123600Z\n20150830/us-east-1/service/aws4_request\n" \
        "bb579772317eb040ac9ed261061d46c1f17a8133879d6129b6e1c25292927e63")
      expect(signature.authorization_header).to eq(test_suite_authorization(
        "host;x-amz-date", "5fa00fa31553b73ebf1942676e86291e8372ff2a2260956d9b8aae1d763fbf31"))
    end

    it "signs get-vanilla-query-order-key-case (sorts query keys)" do
      query = [{"Param2", "value2"}, {"Param1", "value1"}]
      signature = test_suite_signer.sign("GET", "/", query, test_suite_headers, EMPTY_HASH, TEST_SUITE_TIME)

      expect(signature.canonical_request.lines[2]).to eq("Param1=value1&Param2=value2")
      expect(signature.hex_signature).to eq("b97d918cfa904a5beff61c982a1b6f458b799221646efd99d3219ec94cdf2500")
    end

    it "signs get-vanilla-query-unreserved (leaves unreserved bytes alone)" do
      unreserved = "-._~0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
      signature = test_suite_signer.sign("GET", "/", [{unreserved, unreserved}], test_suite_headers, EMPTY_HASH, TEST_SUITE_TIME)

      expect(signature.hex_signature).to eq("9c3e54bfcdf0b19771a7f523ee5669cdf59bc7cc0884027167c21bb143a40197")
    end

    it "signs get-vanilla-utf8-query (percent-encodes UTF-8 bytes)" do
      signature = test_suite_signer.sign("GET", "/", [{"ሴ", "bar"}], test_suite_headers, EMPTY_HASH, TEST_SUITE_TIME)

      expect(signature.canonical_request.lines[2]).to eq("%E1%88%B4=bar")
      expect(signature.hex_signature).to eq("2cdec8eed098649ff3a119c94853b13c643bcf08f8b0a1d91e12c9027818dd04")
    end

    it "signs get-vanilla-empty-query-key" do
      signature = test_suite_signer.sign("GET", "/", [{"Param1", "value1"}], test_suite_headers, EMPTY_HASH, TEST_SUITE_TIME)

      expect(signature.hex_signature).to eq("a67d582fa61cc504c4bae71f336f98b97f1ea3c7a6bfe1b6e45aec72011b9aeb")
    end

    it "signs get-header-value-trim (trims and collapses header values)" do
      headers = test_suite_headers([{"My-Header1", " value1"}, {"My-Header2", %("a   b   c")}])
      signature = test_suite_signer.sign("GET", "/", no_query, headers, EMPTY_HASH, TEST_SUITE_TIME)

      expect(signature.canonical_request).to contain(%(my-header1:value1\nmy-header2:"a b c"\n))
      expect(signature.authorization_header).to eq(test_suite_authorization(
        "host;my-header1;my-header2;x-amz-date", "acc3ed3afb60bb290fc8d2dd0098b9911fcaa05412b367055dee359757a9c736"))
    end

    it "signs get-header-key-duplicate (joins repeated values in order)" do
      headers = test_suite_headers([{"My-Header1", "value2"}, {"My-Header1", "value2"}, {"My-Header1", "value1"}])
      signature = test_suite_signer.sign("GET", "/", no_query, headers, EMPTY_HASH, TEST_SUITE_TIME)

      expect(signature.canonical_request).to contain("my-header1:value2,value2,value1\n")
      expect(signature.hex_signature).to eq("c9d5ea9f3f72853aea855b47ea873832890dbdd183b4468f858259531a5138ea")
    end

    it "signs post-vanilla" do
      signature = test_suite_signer.sign("POST", "/", no_query, test_suite_headers, EMPTY_HASH, TEST_SUITE_TIME)

      expect(signature.hex_signature).to eq("5da7c1a2acd57cee7505fc6676e4e544621c30862966e37dddb68e92efbe5d6b")
    end

    it "signs post-x-www-form-urlencoded (hashes the payload)" do
      headers = HTTP::Headers{
        "Content-Type" => "application/x-www-form-urlencoded",
        "Host"         => "example.amazonaws.com",
        "X-Amz-Date"   => "20150830T123600Z",
      }
      payload_hash = Digest::SHA256.hexdigest("Param1=value1")
      signature = test_suite_signer.sign("POST", "/", no_query, headers, payload_hash, TEST_SUITE_TIME)

      expect(payload_hash).to eq("9095672bbd1f56dfc5b65f3e153adc8731a4a654192329106275f4c7b24d0b6e")
      expect(signature.authorization_header).to eq(test_suite_authorization(
        "content-type;host;x-amz-date", "ff11897932ad3f4e8b18135d722051e5ac45fc38421b1da7b9d196a0fe09473a"))
    end
  end

  describe "#sign with the S3 documentation examples" do
    let(signer) { described_class.new(S3_DOCS_ACCESS_KEY, S3_DOCS_SECRET_KEY, "us-east-1") }

    it "signs the GET Object example" do
      headers = HTTP::Headers{
        "Host"                 => "examplebucket.s3.amazonaws.com",
        "Range"                => "bytes=0-9",
        "x-amz-content-sha256" => EMPTY_HASH,
        "x-amz-date"           => "20130524T000000Z",
      }
      signature = signer.sign("GET", "/test.txt", no_query, headers, EMPTY_HASH, S3_DOCS_TIME)

      expect(signature.canonical_request).to eq(
        "GET\n/test.txt\n\nhost:examplebucket.s3.amazonaws.com\nrange:bytes=0-9\n" \
        "x-amz-content-sha256:#{EMPTY_HASH}\nx-amz-date:20130524T000000Z\n\n" \
        "host;range;x-amz-content-sha256;x-amz-date\n#{EMPTY_HASH}")
      expect(signature.string_to_sign.lines.last).to eq("7344ae5b7ee6c3e7e6b0fe0640412a37625d1fbfff95c48bbb2dc43964946972")
      expect(signature.hex_signature).to eq("f0e8bdb87c964420e857bd35b5d6ed310bd44f0170aba48dd91039c6036bdb41")
    end

    it "signs the PUT Object example" do
      payload_hash = Digest::SHA256.hexdigest("Welcome to Amazon S3.")
      headers = HTTP::Headers{
        "Date"                 => "Fri, 24 May 2013 00:00:00 GMT",
        "Host"                 => "examplebucket.s3.amazonaws.com",
        "x-amz-content-sha256" => payload_hash,
        "x-amz-date"           => "20130524T000000Z",
        "x-amz-storage-class"  => "REDUCED_REDUNDANCY",
      }
      encoded_path = "/#{described_class.uri_encode("test$file.text", keep_slashes: true)}"
      signature = signer.sign("PUT", encoded_path, no_query, headers, payload_hash, S3_DOCS_TIME)

      expect(encoded_path).to eq("/test%24file.text")
      expect(payload_hash).to eq("44ce7dd67c959e0d3524ffac1771dfbba87d2b6b4b4e99e42034a8b803f8b072")
      expect(signature.string_to_sign.lines.last).to eq("9e0e90d9c76de8fa5b200d8c849cd5b8dc7a3be3951ddb7f6a76b4158342019d")
      expect(signature.authorization_header).to eq(
        "AWS4-HMAC-SHA256 Credential=AKIAIOSFODNN7EXAMPLE/20130524/us-east-1/s3/aws4_request, " \
        "SignedHeaders=date;host;x-amz-content-sha256;x-amz-date;x-amz-storage-class, " \
        "Signature=98ad721746da40c64f1a55b78f14c238d841ea1380cd77a1b5971af0ece108bd")
    end
  end

  describe "#presign" do
    it "matches the S3 documentation presigned URL example" do
      signer = described_class.new(S3_DOCS_ACCESS_KEY, S3_DOCS_SECRET_KEY, "us-east-1")
      query_string, signature = signer.presign("GET", "/test.txt", "examplebucket.s3.amazonaws.com", 86_400.seconds, S3_DOCS_TIME)

      expect(signature.canonical_request).to eq(
        "GET\n/test.txt\n" \
        "X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=AKIAIOSFODNN7EXAMPLE%2F20130524%2Fus-east-1%2Fs3%2Faws4_request" \
        "&X-Amz-Date=20130524T000000Z&X-Amz-Expires=86400&X-Amz-SignedHeaders=host\n" \
        "host:examplebucket.s3.amazonaws.com\n\nhost\nUNSIGNED-PAYLOAD")
      expect(query_string).to eq(
        "X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=AKIAIOSFODNN7EXAMPLE%2F20130524%2Fus-east-1%2Fs3%2Faws4_request" \
        "&X-Amz-Date=20130524T000000Z&X-Amz-Expires=86400&X-Amz-SignedHeaders=host" \
        "&X-Amz-Signature=aeeed9bbccd4d02ee5c0109b86d86835f995330da4c265957d157751f604d404")
    end
  end

  describe ".uri_encode" do
    it "encodes reserved and non-ASCII bytes with uppercase hex" do
      expect(described_class.uri_encode("a b+c/é")).to eq("a%20b%2Bc%2F%C3%A9")
    end

    it "keeps slashes for object keys when asked" do
      expect(described_class.uri_encode("dir/a b.jpg", keep_slashes: true)).to eq("dir/a%20b.jpg")
    end
  end

  describe "#inspect" do
    it "leaves the secret key out" do
      signer = described_class.new(S3_DOCS_ACCESS_KEY, S3_DOCS_SECRET_KEY, "us-east-1")
      expect(signer.inspect).not_to contain(S3_DOCS_SECRET_KEY)
    end
  end
end
