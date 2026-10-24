require "../../spec_helper"

Spectator.describe Gemma::Storage::S3 do
  subject do
    Gemma::Storage::S3.new(
      bucket: bucket,
      client: client,
      prefix: prefix,
      upload_options: {"x-amz-acl" => "private"}
    )
  end

  let(client) { Gemma::Storage::S3::Client.new("us-east-2", "test_key", "test_secret") }
  let(bucket) { "test" }
  let(prefix) { nil }
  let(id) { "ex" }
  let(host) { "https://test.s3.us-east-2.amazonaws.com" }

  let(metadata) do
    Gemma::UploadedFile::MetadataType{
      "filename"  => "résumé photo.jpg",
      "mime_type" => "image/jpeg",
      "size"      => "50",
    }
  end

  before_each { WebMock.reset }

  describe "#initialize" do
    context "without `prefix`" do
      it "object_key" do
        expect(subject.object_key(id)).to eq(id)
      end
    end

    context "with `prefix`" do
      let(prefix) { "prefix" }

      it "object_key" do
        expect(subject.object_key(id)).to eq("#{prefix}/#{id}")
      end
    end
  end

  describe "#upload" do
    context "without `prefix`" do
      it "puts the object at the key" do
        WebMock.stub(:put, "#{host}/object").to_return(status: 200, body: "", headers: {"ETag" => "etag"})

        expect(subject.upload(FakeIO.new("hello"), "object")).to be_true
      end
    end

    context "with `prefix`" do
      let(prefix) { "prefix" }

      it "puts the object under the prefix" do
        WebMock.stub(:put, "#{host}/#{prefix}/a/a/a.jpg").to_return(status: 200, body: "")

        expect(subject.upload(FakeIO.new, "a/a/a.jpg")).to be_true
      end
    end

    context "with metadata" do
      it "sends the body, the upload options and an RFC 6266 Content-Disposition, all signed" do
        sent_request = nil
        WebMock.stub(:put, "#{host}/a/a/a.jpg").to_return do |request|
          sent_request = request
          HTTP::Client::Response.new(200)
        end

        expect(subject.upload(FakeIO.new("binary\u0000data"), "a/a/a.jpg", metadata)).to be_true

        request = sent_request
        raise "the PUT never reached the stub" unless request
        expect(WebMock.body(request)).to eq("binary\u0000data")
        expect(request.headers["Content-Disposition"]).to eq(
          %(inline; filename="r%3Fsum%3F photo.jpg"; filename*=UTF-8''r%C3%A9sum%C3%A9%20photo.jpg))
        expect(request.headers["x-amz-acl"]).to eq("private")
        expect(request.headers["X-Amz-Content-Sha256"]).to eq(Digest::SHA256.hexdigest("binary\u0000data"))
        expect(request.headers["Authorization"]).to contain("content-disposition;host;x-amz-acl;x-amz-content-sha256;x-amz-date")
        expect(request.headers.has_key?("metadata")).to be_false
      end
    end

    context "when the service refuses the upload" do
      it "raises a ResponseError with the status code and raw body" do
        WebMock.stub(:put, "#{host}/denied.jpg").to_return(
          status: 403, body: "<Error><Code>AccessDenied</Code><Message>Access Denied</Message></Error>")

        expect { subject.upload(FakeIO.new, "denied.jpg") }.to raise_error(Gemma::Storage::S3::ResponseError)

        error = begin
          subject.upload(FakeIO.new, "denied.jpg")
          nil
        rescue exception : Gemma::Storage::S3::ResponseError
          exception
        end
        raise "expected a ResponseError" unless error
        expect(error.status_code).to eq(403)
        expect(error.response_body).to contain("<Code>AccessDenied</Code>")
        expect(error.message).to eq(
          "S3 PUT /denied.jpg failed with HTTP 403: <Error><Code>AccessDenied</Code><Message>Access Denied</Message></Error>")
      end
    end
  end

  describe "#exists?" do
    it "is true when HEAD succeeds" do
      WebMock.stub(:head, "#{host}/a/a/a.jpg").to_return(status: 200, headers: {"Content-Type" => "binary/octet-stream"})
      expect(subject.exists?("a/a/a.jpg")).to be_true
    end

    it "is false for 404" do
      WebMock.stub(:head, "#{host}/ex.jpg").to_return(status: 404)
      expect(subject.exists?("ex.jpg")).to be_false
    end

    it "is false for 403, which S3 sends for missing keys without list permission" do
      WebMock.stub(:head, "#{host}/ex.jpg").to_return(status: 403)
      expect(subject.exists?("ex.jpg")).to be_false
    end

    it "raises for a server error" do
      WebMock.stub(:head, "#{host}/ex.jpg").to_return(status: 503)
      expect { subject.exists?("ex.jpg") }.to raise_error(Gemma::Storage::S3::ResponseError)
    end
  end

  describe "#url" do
    context "without `prefix`" do
      it "returns a presigned virtual-hosted URL" do
        url = subject.url("foo.jpg")

        expect(url).to start_with("#{host}/foo.jpg?X-Amz-Algorithm=AWS4-HMAC-SHA256")
        expect(url).to contain("X-Amz-Expires=86400")
        expect(url).to contain("X-Amz-Signature=")
      end
    end

    context "with `prefix`" do
      let(prefix) { "prefix" }

      it "returns a presigned URL under the prefix" do
        expect(subject.url("foo.jpg")).to start_with("#{host}/#{prefix}/foo.jpg?")
      end
    end

    it "accepts expires_in as a Time::Span or seconds" do
      expect(subject.url("foo.jpg", expires_in: 1.hour)).to contain("X-Amz-Expires=3600")
      expect(subject.url("foo.jpg", expires_in: 600)).to contain("X-Amz-Expires=600")
    end
  end

  describe "#open" do
    context "without `prefix`" do
      it "returns an IO holding the whole object, rewound to position 0" do
        WebMock.stub(:get, "#{host}/foo.jpg").to_return(body_io: IO::Memory.new("object bytes"))

        io = subject.open("foo.jpg")

        expect(io).to be_kind_of(IO::Memory)
        expect(io.pos).to eq(0)
        expect(io.gets_to_end).to eq("object bytes")
      end
    end

    context "with `prefix`" do
      let(prefix) { "prefix" }

      it "reads the object under the prefix" do
        WebMock.stub(:get, "#{host}/#{prefix}/foo.jpg").to_return(body_io: IO::Memory.new("prefixed"))

        expect(subject.open("foo.jpg").gets_to_end).to eq("prefixed")
      end
    end

    it "raises Gemma::FileNotFound for a missing object" do
      WebMock.stub(:get, "#{host}/missing.jpg").to_return(
        status: 404, body: "<Error><Code>NoSuchKey</Code></Error>")

      expect { subject.open("missing.jpg") }.to raise_error(Gemma::FileNotFound, /NoSuchKey/)
    end
  end

  describe "#delete" do
    context "without `prefix`" do
      it "deletes objects" do
        WebMock.stub(:delete, "#{host}/foo.jpg").to_return(status: 204)
        expect(subject.delete("foo.jpg")).to be_true
      end
    end

    context "with `prefix`" do
      let(prefix) { "prefix" }

      it "deletes objects" do
        WebMock.stub(:delete, "#{host}/#{prefix}/foo.jpg").to_return(status: 204)
        expect(subject.delete("foo.jpg")).to be_true
      end
    end
  end
end
