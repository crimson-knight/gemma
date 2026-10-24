require "../spec_helper"

# Reads like a socket or request body: forward only.
private class ForwardOnlyIO < IO
  def initialize(content : String)
    @source = IO::Memory.new(content)
  end

  def read(slice : Bytes) : Int32
    @source.read(slice)
  end

  def write(slice : Bytes) : NoReturn
    raise IO::Error.new("read-only")
  end

  def rewind
    raise IO::Error.new("ForwardOnlyIO cannot rewind")
  end

  def seek(offset, whence : IO::Seek = IO::Seek::Set)
    raise IO::Error.new("ForwardOnlyIO cannot seek")
  end
end

private class FiveMegabyteUploader < Gemma::Uploader
  def max_size : Int64?
    5_000_000_i64
  end
end

# The shape of `Amber::Router::File`.
private record MultipartPart, file : File, filename : String?, headers : HTTP::Headers

describe "Gemma#upload" do
  before_each { reset_storages }

  it "records size and MIME type read from the bytes" do
    uploaded_file = uploader.upload(image)

    uploaded_file.size.should eq(File.size(File.join(SPEC_SUPPORT_DIRECTORY, "300x300.png")))
    uploaded_file.mime_type.should eq("image/png")
    uploaded_file.original_filename.should eq("300x300.png")
  end

  it "streams a forward-only IO without rewinding it" do
    content = "x" * (Gemma::SNIFF_BYTES + 10_000)
    uploaded_file = uploader.upload(ForwardOnlyIO.new(content))

    uploaded_file.size.should eq(content.bytesize)
    uploaded_file.open(&.gets_to_end).should eq(content)
  end

  it "leaves the caller's file open" do
    file = image
    uploader.upload(file)

    file.closed?.should be_false
  end

  context "with a size limit" do
    it "refuses a 6 MB upload past a 5,000,000-byte limit and stores nothing" do
      six_megabytes = IO::Memory.new(Bytes.new(6_000_000, 0x61_u8))

      expect_raises(Gemma::FileTooLarge) do
        FiveMegabyteUploader.new("store").upload(six_megabytes)
      end

      memory_storage("store").store.should be_empty
    end

    it "accepts an upload at the limit" do
      FiveMegabyteUploader.new("store").upload(IO::Memory.new(Bytes.new(5_000_000))).size.should eq(5_000_000)
    end

    it "keeps the existing file when a replacement is too large" do
      original = uploader.upload(fakeio("12345"))

      expect_raises(Gemma::FileTooLarge) do
        uploader.upload(fakeio("123456"), location: original.id, max_size: 5_i64)
      end

      original.open(&.gets_to_end).should eq("12345")
    end

    it "keeps the existing file on FileSystem, where the bytes stream to disk" do
      with_file_system_storages do |_root|
        original = uploader.upload(fakeio("12345"))

        expect_raises(Gemma::FileTooLarge) do
          uploader.upload(IO::Memory.new("x" * 2_000_000), location: original.id, max_size: 1_000_000_i64)
        end

        original.open(&.gets_to_end).should eq("12345")
        storage = original.storage
        raise "expected a FileSystem storage" unless storage.is_a?(Gemma::Storage::FileSystem)
        Dir.children(File.dirname(storage.path(original.id))).should eq([original.id])
      end
    end

    it "takes a limit per call" do
      expect_raises(Gemma::FileTooLarge) do
        uploader.upload(fakeio("12345"), max_size: 4_i64)
      end
    end

    it "applies to promotion from another storage" do
      cached = uploader("cache").upload(fakeio("12345"))

      expect_raises(Gemma::FileTooLarge) do
        uploader("store").upload(cached, max_size: 4_i64)
      end
      memory_storage("store").store.should be_empty
    end
  end

  context "copying an UploadedFile" do
    it "reads the type from the bytes, not from the source's metadata" do
      cached = uploader("cache").upload(fakeio("plain text"))
      forged = Gemma::UploadedFile.new(cached.id, "cache", Gemma::Metadata.new(filename: "a.png", mime_type: "image/png", size: 1_i64))

      stored = uploader("store").upload(forged)

      stored.mime_type.should eq("text/plain")
      stored.size.should eq("plain text".bytesize)
      stored.id.should end_with(".txt")
      stored.original_filename.should eq("a.png")
    end
  end

  context "with caller metadata" do
    it "keeps custom fields and the filename" do
      uploaded_file = uploader.upload(fakeio("file"), metadata: {"album" => "trips", "filename" => "../a.txt"})

      uploaded_file.metadata.extra["album"].should eq("trips")
      uploaded_file.original_filename.should eq("a.txt")
    end

    it "cannot set size, MIME type or dimensions" do
      uploaded_file = uploader.upload(fakeio("file"), metadata: {"size" => "1", "mime_type" => "image/png", "width" => "9"})

      uploaded_file.size.should eq(4)
      uploaded_file.mime_type.should eq("text/plain")
      uploaded_file.width.should be_nil
      uploaded_file.metadata.extra.should be_empty
    end

    it "records the declared Content-Type without using it" do
      uploaded_file = uploader.upload(fakeio("file", content_type: "image/png"))

      uploaded_file.mime_type.should eq("text/plain")
      uploaded_file.metadata.extra["declared_content_type"].should eq("image/png")
    end
  end

  context "generating a location" do
    it "uses 32 hex characters and the client's extension when it fits the type" do
      uploader.upload(fakeio("file", filename: "notes.TXT")).id.should match(/\A[0-9a-f]{32}\.txt\z/)
      uploader.upload(image("320x180.jpg"), filename: "photo.jpeg").id.should match(/\A[0-9a-f]{32}\.jpeg\z/)
    end

    it "uses the detected type's extension when the client's does not fit" do
      uploader.upload(fakeio("<script>alert(1)</script>", filename: "page.html")).id.should match(/\A[0-9a-f]{32}\.txt\z/)
      uploader.upload(image, filename: "photo.gif").id.should match(/\A[0-9a-f]{32}\.png\z/)
    end

    it "uses no extension for an unknown type" do
      uploader.upload(fakeio("\u0000\u0001", filename: "x.html")).id.should match(/\A[0-9a-f]{32}\z/)
    end

    it "uses a given location" do
      uploader.upload(fakeio, location: "a/b.txt").id.should eq("a/b.txt")
    end
  end

  context "given a multipart part" do
    it "takes the client's filename and Content-Type from the part" do
      headers = HTTP::Headers{"Content-Type" => "text/plain; charset=utf-8"}
      part = MultipartPart.new(tempfile("hello", "amber-upload"), "../notes.txt", headers)

      uploaded_file = uploader.upload(part)

      uploaded_file.original_filename.should eq("notes.txt")
      uploaded_file.metadata.extra["declared_content_type"].should eq("text/plain")
      uploaded_file.id.should end_with(".txt")
    end
  end
end
