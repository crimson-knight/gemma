require "../spec_helper"

private def cached_file(id : String = "foo", filename : String? = nil, mime_type : String? = nil, size : Int64? = nil) : Gemma::UploadedFile
  Gemma::UploadedFile.new(id, "cache", Gemma::Metadata.new(filename: filename, mime_type: mime_type, size: size))
end

describe Gemma::UploadedFile do
  before_each { reset_storages }

  describe "#initialize" do
    it "starts with empty metadata" do
      metadata = Gemma::UploadedFile.new("foo", "cache").metadata

      metadata.size.should be_nil
      metadata.extra.should be_empty
    end
  end

  describe "#original_filename" do
    it "returns nil without a filename in metadata" do
      cached_file.original_filename.should be_nil
    end

    it "returns the filename from metadata" do
      cached_file(filename: "foo.jpg").original_filename.should eq("foo.jpg")
    end
  end

  describe "#extension" do
    it "reads the extension from the id" do
      cached_file(id: "foo.jpg").extension.should eq("jpg")
    end

    it "is nil when the id has no extension" do
      cached_file(id: "foo").extension.should be_nil
    end

    it "reads the extension from the filename in metadata" do
      cached_file(filename: "foo.jpg").extension.should eq("jpg")
    end

    it "is nil when the filename in metadata has no extension" do
      cached_file(filename: "foo").extension.should be_nil
    end

    it "prefers the extension from the id over the one from the filename" do
      cached_file(id: "foo.jpg", filename: "foo.png").extension.should eq("jpg")
    end

    it "downcases an uppercase extension" do
      cached_file(id: "foo.JPG").extension.should eq("jpg")
      cached_file(filename: "foo.PNG").extension.should eq("png")
    end
  end

  describe "#size and #mime_type" do
    it "read the metadata" do
      file = cached_file(size: 50_i64, mime_type: "image/jpeg")

      file.size.should eq(50)
      file.mime_type.should eq("image/jpeg")
      file.content_type.should eq("image/jpeg")
    end

    it "are nil when unknown" do
      cached_file.size.should be_nil
      cached_file.mime_type.should be_nil
    end
  end

  describe "#width, #height and #dimensions" do
    it "read the metadata" do
      file = Gemma::UploadedFile.new("foo", "cache", Gemma::Metadata.new(width: 300, height: 200))

      file.width.should eq(300)
      file.height.should eq(200)
      file.dimensions.should eq({300, 200})
    end

    it "have no dimensions when one side is unknown" do
      Gemma::UploadedFile.new("foo", "cache", Gemma::Metadata.new(width: 300)).dimensions.should be_nil
    end
  end

  describe "#url" do
    it "delegates to the storage" do
      cached_file.url.should eq("memory://foo")
    end
  end

  describe "#exists?" do
    it "delegates to the storage" do
      uploader.upload(fakeio).exists?.should be_true
      cached_file.exists?.should be_false
    end
  end

  describe "#open" do
    it "returns a new IO each time, which the caller closes" do
      uploaded_file = uploader.upload(fakeio("file"))
      first = uploaded_file.open
      second = uploaded_file.open

      first.should_not be(second)
      first.gets_to_end.should eq("file")
      second.gets_to_end.should eq("file")
      first.close
      second.close
    end

    it "yields the IO, returns the block's value and closes the IO" do
      uploaded_file = uploader.upload(fakeio("file"))
      yielded_io = nil

      content = uploaded_file.open do |io|
        yielded_io = io
        io.gets_to_end
      end

      content.should eq("file")
      yielded_io.try(&.closed?).should be_true
    end

    it "closes the IO when the block raises" do
      uploaded_file = uploader.upload(fakeio)
      yielded_io = nil

      expect_raises(Exception, "error occurred") do
        uploaded_file.open do |io|
          yielded_io = io
          raise "error occurred"
        end
      end

      yielded_io.try(&.closed?).should be_true
    end
  end

  describe "#download" do
    it "streams the content into an open, rewound tempfile" do
      downloaded = uploader.upload(fakeio("file")).download
      begin
        downloaded.closed?.should be_false
        downloaded.gets_to_end.should eq("file")
      ensure
        downloaded.delete
        downloaded.close
      end
    end

    it "uses the extension of the id" do
      downloaded = uploader.upload(fakeio, location: "foo.jpg").download
      begin
        downloaded.path.should end_with(".jpg")
      ensure
        downloaded.delete
        downloaded.close
      end
    end

    it "with a block, returns the block's value and deletes the tempfile" do
      uploaded_file = uploader.upload(fakeio("file"))
      path = ""

      content = uploaded_file.download do |tempfile|
        path = tempfile.path
        tempfile.gets_to_end
      end

      content.should eq("file")
      File.exists?(path).should be_false
    end

    it "deletes the tempfile when streaming fails" do
      missing = Gemma::UploadedFile.new("missing", "store")
      before = Dir.children(Dir.tempdir).count(&.starts_with?("gemma"))

      expect_raises(Gemma::FileNotFound) { missing.download }

      Dir.children(Dir.tempdir).count(&.starts_with?("gemma")).should eq(before)
    end
  end

  describe "#stream" do
    it "copies the content into the destination" do
      destination = IO::Memory.new
      uploader.upload(fakeio("content")).stream(destination)

      destination.to_s.should eq("content")
    end
  end

  describe "#replace" do
    it "uploads another file to the same location" do
      uploaded_file = uploader.upload(fakeio("file"))
      replaced = uploaded_file.replace(fakeio("replaced"))

      replaced.id.should eq(uploaded_file.id)
      replaced.open(&.gets_to_end).should eq("replaced")
      replaced.size.should eq("replaced".bytesize)
    end
  end

  describe "#delete" do
    it "delegates to the storage" do
      uploaded_file = uploader.upload(fakeio)
      uploaded_file.delete

      uploaded_file.exists?.should be_false
    end
  end

  describe "#==" do
    it "compares the id and the storage" do
      cached_file(id: "a", size: 1_i64).should eq(cached_file(id: "a", size: 2_i64))
      cached_file(id: "a").should_not eq(cached_file(id: "b"))
      cached_file(id: "a").should_not eq(Gemma::UploadedFile.new("a", "store"))
    end
  end

  describe "JSON" do
    it "writes the shape Gemma has always stored" do
      metadata = Gemma::Metadata.new(filename: "a.png", size: 753_i64, mime_type: "image/png", width: 300, height: 300)
      metadata.extra["album"] = "trips"

      JSON.parse(Gemma::UploadedFile.new("foo.png", "store", metadata).to_json).should eq(JSON.parse(<<-JSON))
        {"id": "foo.png", "storage_key": "store", "metadata":
          {"filename": "a.png", "size": 753, "mime_type": "image/png", "width": 300, "height": 300, "album": "trips"}}
        JSON
    end

    it "round-trips" do
      metadata = Gemma::Metadata.new(filename: "a.png", size: 753_i64, mime_type: "image/png", width: 300, height: 300)
      metadata.extra["album"] = "trips"
      file = Gemma::UploadedFile.new("foo.png", "store", metadata)

      loaded = Gemma::UploadedFile.from_json(file.to_json)

      loaded.should eq(file)
      loaded.metadata.should eq(metadata)
    end
  end
end
