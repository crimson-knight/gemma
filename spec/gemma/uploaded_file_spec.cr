require "../spec_helper"

private def cached_file(id : String = "foo", filename : String? = nil, mime_type : String? = nil, size : Int32 | String? = nil) : Gemma::UploadedFile
  metadata = Gemma::UploadedFile::MetadataType{
    "filename"  => filename,
    "mime_type" => mime_type,
    "size"      => size,
  }
  Gemma::UploadedFile.new(id, "cache", metadata)
end

describe Gemma::UploadedFile do
  after_each { reset_storages }

  describe "#initialize" do
    it "initializes metadata if absent" do
      Gemma::UploadedFile.new("foo", "cache").metadata.should be_a(Gemma::UploadedFile::MetadataType)
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

    it "is nil without a filename in metadata" do
      cached_file.extension.should be_nil
    end

    it "prefers the extension from the id over the one from the filename" do
      cached_file(id: "foo.jpg", filename: "foo.png").extension.should eq("jpg")
    end

    it "downcases an uppercase extension in the id" do
      cached_file(id: "foo.JPG").extension.should eq("jpg")
    end

    it "downcases an uppercase extension in the filename" do
      cached_file(filename: "foo.PNG").extension.should eq("png")
    end
  end

  describe "#size" do
    it "returns nil without a size in metadata" do
      cached_file.size.should be_nil
    end

    it "returns the size from metadata" do
      cached_file(size: 50).size.should eq(50)
    end

    it "converts a String size to an integer" do
      cached_file(size: "50").size.should eq(50)
    end
  end

  describe "#mime_type" do
    it "returns the mime_type from metadata" do
      cached_file(mime_type: "image/jpeg").mime_type.should eq("image/jpeg")
    end

    it "has a #content_type alias" do
      cached_file(mime_type: "image/jpeg").content_type.should eq("image/jpeg")
    end

    it "returns nil without a mime_type in metadata" do
      cached_file.mime_type.should be_nil
    end
  end

  describe "#close" do
    it "closes the underlying IO object" do
      uploaded_file = uploader.upload(fakeio)
      io = uploaded_file.io
      uploaded_file.close

      io.closed?.should be_true
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
    it "returns the underlying IO if no block is given" do
      uploaded_file = uploader.upload(fakeio)

      uploaded_file.open.should be_a(IO)
      uploaded_file.open.closed?.should be_false
    end

    it "closes the previous IO" do
      uploaded_file = uploader.upload(fakeio)
      io1 = uploaded_file.open
      io2 = uploaded_file.open

      io1.should_not be(io2)
      io1.closed?.should be_true
      io2.closed?.should be_false
    end

    it "yields to the block if one is given" do
      uploaded_file = uploader.upload(fakeio)

      called = false
      uploaded_file.open { called = true }
      called.should be_true
    end

    it "yields the opened IO" do
      uploaded_file = uploader.upload(fakeio("file"))
      uploaded_file.open do |io|
        io.should be_a(IO)
        io.gets_to_end.should eq("file")
      end
    end

    it "makes itself open as well" do
      uploaded_file = uploader.upload(fakeio)
      uploaded_file.open do |io|
        io.should be(uploaded_file.io)
      end
    end

    it "closes the IO after the block finishes" do
      uploaded_file = uploader.upload(fakeio)

      yielded_io = IO::Memory.new
      uploaded_file.open { |io| yielded_io = io }
      expect_raises(IO::Error) { yielded_io.gets_to_end }
    end

    it "can be read again after the block" do
      uploaded_file = uploader.upload(fakeio("file"))
      uploaded_file.open { }

      uploaded_file.gets_to_end.should eq("file")
    end

    it "opens even if it was closed" do
      uploaded_file = uploader.upload(fakeio("file"))
      uploaded_file.gets_to_end
      uploaded_file.close
      uploaded_file.open do |io|
        io.gets_to_end.should eq("file")
      end
    end

    it "closes the file even if an error occurred" do
      uploaded_file = uploader.upload(fakeio)
      yielded_io = IO::Memory.new

      expect_raises(Exception, "error occurred") do
        uploaded_file.open do |io|
          yielded_io = io
          raise "error occurred"
        end
      end

      yielded_io.closed?.should be_true
    end
  end

  describe "#download" do
    it "downloads file content to a Tempfile" do
      downloaded = uploader.upload(fakeio("file")).download

      downloaded.should be_a(File)
      downloaded.closed?.should be_false
      downloaded.gets_to_end.should eq("file")
    end

    it "applies the extension from #id" do
      uploaded_file = uploader.upload(fakeio, location: "foo.jpg")

      uploaded_file.download.path.should end_with(".jpg")
    end

    it "applies the extension from #original_filename" do
      uploaded_file = uploader.upload(fakeio(filename: "foo.jpg"), location: "foo")

      uploaded_file.download.path.should end_with(".jpg")
    end

    it "yields the tempfile if a block is given" do
      uploader.upload(fakeio).download do |tempfile|
        tempfile.should be_a(File)
      end
    end

    it "returns the block's return value" do
      uploader.upload(fakeio).download { |_tempfile| "result" }.should eq("result")
    end

    it "closes and deletes the tempfile after the block" do
      uploaded_file = uploader.upload(fakeio)

      tempfile = uploaded_file.download do |yielded_tempfile|
        yielded_tempfile.closed?.should be_false
        yielded_tempfile
      end

      tempfile.closed?.should be_true
      File.exists?(tempfile.path).should be_false
    end
  end

  describe "#stream" do
    it "opens and closes the file when it was not open" do
      uploaded_file = uploader.upload(fakeio("content"))
      destination = IO::Memory.new
      uploaded_file.stream(destination)

      destination.to_s.should eq("content")
      uploaded_file.opened?.should be_false
    end
  end

  describe "#replace" do
    it "uploads another file to the same location" do
      uploaded_file = uploader.upload(fakeio("file"))
      new_uploaded_file = uploaded_file.replace(fakeio("replaced"))

      new_uploaded_file.id.should eq(uploaded_file.id)
      new_uploaded_file.gets_to_end.should eq("replaced")
      new_uploaded_file.size.should eq("replaced".size)
    end
  end

  describe "#delete" do
    it "delegates to the storage" do
      uploaded_file = uploader.upload(fakeio)
      uploaded_file.delete

      uploaded_file.exists?.should be_false
    end
  end

  describe "#data" do
    it "returns the uploaded file data hash" do
      metadata = Gemma::UploadedFile::MetadataType{"foo" => "bar"}
      uploaded_file = Gemma::UploadedFile.new("foo", "cache", metadata)

      uploaded_file.data.should eq({
        "id"          => "foo",
        "storage_key" => "cache",
        "metadata"    => metadata,
      })
    end
  end
end
