require "../spec_helper"

describe Gemma::CachedFileReference do
  describe ".valid_id?" do
    {"5127d51a19fb01bcb0c5b407d418abfc", "5127d51a19fb01bcb0c5b407d418abfc.jpg", "test/abc.pdf", "a_b-c.d"}.each do |generated_id|
      it "accepts #{generated_id.inspect}" do
        Gemma::CachedFileReference.valid_id?(generated_id).should be_true
      end
    end

    {"", "../etc/hosts", "a/../b", "/etc/hosts", ".hidden", "a//b", "a/./b", "with space", "a\\b", "x" * 1025}.each do |hostile_id|
      it "rejects #{hostile_id.inspect[0, 40]}" do
        Gemma::CachedFileReference.valid_id?(hostile_id).should be_false
      end
    end
  end

  describe ".parse" do
    it "reads the id, the storage key and the client's filename" do
      reference = Gemma::CachedFileReference.parse(%({"id":"abc","storage_key":"cache","metadata":{"filename":"a.png","size":1}}))

      reference.id.should eq("abc")
      reference.storage_key.should eq("cache")
      reference.metadata.filename.should eq("a.png")
    end

    it "accepts a reference without metadata" do
      Gemma::CachedFileReference.parse(%({"id":"abc","storage_key":"cache"})).metadata.filename.should be_nil
    end

    it "raises Gemma::NotCached for JSON that is not a reference" do
      expect_raises(Gemma::NotCached) { Gemma::CachedFileReference.parse(%({"storage_key":"cache"})) }
      expect_raises(Gemma::NotCached) { Gemma::CachedFileReference.parse("not json") }
    end
  end
end

describe "Gemma::Attacher#attach_cached with a cached file reference" do
  before_each { reset_storages }

  it "attaches a file the cache holds, with metadata read from the stored bytes" do
    cached = Gemma.upload(fakeio("cached bytes"), "cache")
    attacher = Gemma::Attacher.new

    attacher.attach_cached(%({"id":"#{cached.id}","storage_key":"cache","metadata":{"filename":"report.pdf","size":999}}))

    attached = attacher.file || fail("expected an attached file")
    attached.id.should eq(cached.id)
    attached.storage_key.should eq("cache")
    attached.size.should eq("cached bytes".bytesize)
    attached.original_filename.should eq("report.pdf")
    attacher.changed?.should be_true
  end

  it "accepts the same reference as a Hash" do
    cached = Gemma.upload(fakeio("cached bytes"), "cache")
    attacher = Gemma::Attacher.new

    reference = {"id" => cached.id, "storage_key" => "cache"}
    attacher.attach_cached(reference)

    attacher.file.try(&.id).should eq(cached.id)
  end

  it "checks a deserialized UploadedFile like a client reference" do
    stored = Gemma.upload(fakeio, "store")
    forged = Gemma::UploadedFile.from_json(%({"id":"#{stored.id}","storage_key":"store","metadata":{}}))

    expect_raises(Gemma::NotCached) { Gemma::Attacher.new.attach_cached(forged) }
  end

  it "re-reads the metadata of a cached UploadedFile instead of trusting it" do
    cached = Gemma.upload(fakeio("cached bytes"), "cache")
    forged = Gemma::UploadedFile.from_json(%({"id":"#{cached.id}","storage_key":"cache","metadata":{"size":1}}))
    attacher = Gemma::Attacher.new

    attacher.attach_cached(forged)

    attacher.file.try(&.size).should eq("cached bytes".bytesize)
  end

  it "refuses a file in permanent storage" do
    stored = Gemma.upload(fakeio, "store")

    expect_raises(Gemma::NotCached) do
      Gemma::Attacher.new.attach_cached(%({"id":"#{stored.id}","storage_key":"store"}))
    end
  end

  it "refuses an id the cache does not hold" do
    expect_raises(Gemma::NotCached) do
      Gemma::Attacher.new.attach_cached(%({"id":"0123456789abcdef0123456789abcdef","storage_key":"cache"}))
    end
  end

  it "refuses an id that is not a generated location" do
    expect_raises(Gemma::InvalidLocation) do
      Gemma::Attacher.new.attach_cached(%({"id":"../secrets.txt","storage_key":"cache"}))
    end
  end
end

describe "Gemma#upload" do
  before_each { reset_storages }

  it "generates a 32-character hex location from a secure source" do
    uploader.upload(fakeio("\u0000")).id.should match(/\A[0-9a-f]{32}\z/)
  end

  it "keeps the client's extension, lowercased, when it fits the detected type" do
    uploader.upload(image("320x180.jpg"), filename: "photo.JPG").id.should match(/\A[0-9a-f]{32}\.jpg\z/)
  end

  it "streams an UploadedFile from another storage" do
    cached = Gemma.upload(fakeio("cached bytes"), "cache")

    stored = Gemma.upload(cached, "store")

    stored.storage_key.should eq("store")
    stored.open(&.gets_to_end).should eq("cached bytes")
    cached.exists?.should be_true
  end
end
