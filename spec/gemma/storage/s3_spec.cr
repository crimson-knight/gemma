require "../../spec_helper"

private S3_SPEC_HOST = "https://test.s3.us-east-2.amazonaws.com"

private def s3_storage(prefix : String? = nil) : Gemma::Storage::S3
  client = Gemma::Storage::S3::Client.new("us-east-2", "test_key", "test_secret")
  Gemma::Storage::S3.new(
    bucket: "test",
    client: client,
    prefix: prefix,
    upload_options: {"x-amz-acl" => "private"}
  )
end

private def s3_metadata : Gemma::UploadedFile::MetadataType
  Gemma::UploadedFile::MetadataType{
    "filename"  => "résumé photo.jpg",
    "mime_type" => "image/jpeg",
    "size"      => "50",
  }
end

describe Gemma::Storage::S3 do
  describe "#object_key" do
    it "is the id without a prefix" do
      s3_storage.object_key("ex").should eq("ex")
    end

    it "puts the prefix in front of the id" do
      s3_storage(prefix: "prefix").object_key("ex").should eq("prefix/ex")
    end
  end

  describe "#upload" do
    it "puts the object at the key" do
      WebMock.stub(:put, "#{S3_SPEC_HOST}/object").to_return(status: 200, body: "", headers: {"ETag" => "etag"})

      s3_storage.upload(FakeIO.new("hello"), "object")
    end

    it "puts the object under the prefix" do
      WebMock.stub(:put, "#{S3_SPEC_HOST}/prefix/a/a/a.jpg").to_return(status: 200, body: "")

      s3_storage(prefix: "prefix").upload(FakeIO.new, "a/a/a.jpg")
    end

    it "sends the body, the upload options, Content-Type and an RFC 6266 Content-Disposition, all signed" do
      sent_request = nil
      WebMock.stub(:put, "#{S3_SPEC_HOST}/a/a/a.jpg").to_return do |request|
        sent_request = request
        HTTP::Client::Response.new(200)
      end

      s3_storage.upload(FakeIO.new("binary\u0000data"), "a/a/a.jpg", s3_metadata)

      request = sent_request
      raise "the PUT never reached the stub" unless request
      WebMock.body(request).should eq("binary\u0000data")
      request.headers["Content-Disposition"].should eq(
        %(inline; filename="r%3Fsum%3F photo.jpg"; filename*=UTF-8''r%C3%A9sum%C3%A9%20photo.jpg))
      request.headers["Content-Type"].should eq("image/jpeg")
      request.headers["x-amz-acl"].should eq("private")
      request.headers["X-Amz-Content-Sha256"].should eq(Digest::SHA256.hexdigest("binary\u0000data"))
      request.headers["Authorization"].should contain("content-disposition;content-type;host;x-amz-acl;x-amz-content-sha256;x-amz-date")
      request.headers.has_key?("metadata").should be_false
    end

    it "raises a ResponseError with the status code and raw body when the service refuses" do
      WebMock.stub(:put, "#{S3_SPEC_HOST}/denied.jpg").to_return(
        status: 403, body: "<Error><Code>AccessDenied</Code><Message>Access Denied</Message></Error>")

      error = expect_raises(Gemma::Storage::S3::ResponseError) do
        s3_storage.upload(FakeIO.new, "denied.jpg")
      end
      error.status_code.should eq(403)
      error.response_body.should contain("<Code>AccessDenied</Code>")
      error.message.should eq(
        "S3 PUT /denied.jpg failed with HTTP 403: <Error><Code>AccessDenied</Code><Message>Access Denied</Message></Error>")
    end
  end

  describe "#exists?" do
    it "is true when HEAD succeeds" do
      WebMock.stub(:head, "#{S3_SPEC_HOST}/a/a/a.jpg").to_return(status: 200, headers: {"Content-Type" => "binary/octet-stream"})
      s3_storage.exists?("a/a/a.jpg").should be_true
    end

    it "is false for 404" do
      WebMock.stub(:head, "#{S3_SPEC_HOST}/ex.jpg").to_return(status: 404)
      s3_storage.exists?("ex.jpg").should be_false
    end

    it "is false for 403, which S3 sends for missing keys without list permission" do
      WebMock.stub(:head, "#{S3_SPEC_HOST}/ex.jpg").to_return(status: 403)
      s3_storage.exists?("ex.jpg").should be_false
    end

    it "raises for a server error" do
      WebMock.stub(:head, "#{S3_SPEC_HOST}/ex.jpg").to_return(status: 503)
      expect_raises(Gemma::Storage::S3::ResponseError) { s3_storage.exists?("ex.jpg") }
    end
  end

  describe "#url" do
    it "returns a presigned virtual-hosted URL" do
      url = s3_storage.url("foo.jpg")

      url.should start_with("#{S3_SPEC_HOST}/foo.jpg?X-Amz-Algorithm=AWS4-HMAC-SHA256")
      url.should contain("X-Amz-Expires=86400")
      url.should contain("X-Amz-Signature=")
    end

    it "returns a presigned URL under the prefix" do
      s3_storage(prefix: "prefix").url("foo.jpg").should start_with("#{S3_SPEC_HOST}/prefix/foo.jpg?")
    end

    it "accepts expires_in as a Time::Span or seconds" do
      s3_storage.url("foo.jpg", expires_in: 1.hour).should contain("X-Amz-Expires=3600")
      s3_storage.url("foo.jpg", expires_in: 600).should contain("X-Amz-Expires=600")
    end
  end

  describe "#open" do
    it "returns an IO holding the whole object, rewound to position 0" do
      WebMock.stub(:get, "#{S3_SPEC_HOST}/foo.jpg").to_return(body_io: IO::Memory.new("object bytes"))

      io = s3_storage.open("foo.jpg")

      io.should be_a(IO::Memory)
      io.pos.should eq(0)
      io.gets_to_end.should eq("object bytes")
    end

    it "reads the object under the prefix" do
      WebMock.stub(:get, "#{S3_SPEC_HOST}/prefix/foo.jpg").to_return(body_io: IO::Memory.new("prefixed"))

      s3_storage(prefix: "prefix").open("foo.jpg").gets_to_end.should eq("prefixed")
    end

    it "raises Gemma::FileNotFound for a missing object" do
      WebMock.stub(:get, "#{S3_SPEC_HOST}/missing.jpg").to_return(
        status: 404, body: "<Error><Code>NoSuchKey</Code></Error>")

      expect_raises(Gemma::FileNotFound, /NoSuchKey/) { s3_storage.open("missing.jpg") }
    end
  end

  describe "#delete" do
    it "deletes objects" do
      WebMock.stub(:delete, "#{S3_SPEC_HOST}/foo.jpg").to_return(status: 204)
      s3_storage.delete("foo.jpg").should be_nil
    end

    it "deletes objects under the prefix" do
      WebMock.stub(:delete, "#{S3_SPEC_HOST}/prefix/foo.jpg").to_return(status: 204)
      s3_storage(prefix: "prefix").delete("foo.jpg").should be_nil
    end

    it "raises when the service refuses the delete" do
      WebMock.stub(:delete, "#{S3_SPEC_HOST}/foo.jpg").to_return(status: 403)
      expect_raises(Gemma::Storage::S3::ResponseError) { s3_storage.delete("foo.jpg") }
    end
  end
end
