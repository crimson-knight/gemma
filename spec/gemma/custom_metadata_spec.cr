require "../spec_helper"

class UploaderWithCustomMetadata < Gemma::Uploader
  def custom_metadata(io : IO, metadata : Gemma::Metadata) : Hash(String, String)
    text = io.gets_to_end

    {
      "custom"      => "value",
      "first_bytes" => text,
      "twice"       => text * 2,
      "seen_type"   => metadata.mime_type || "unknown",
      "size"        => "1",
    }
  end
end

describe "Gemma::Uploader#custom_metadata" do
  before_each { reset_storages }

  it "adds fields computed from the upload's bytes" do
    uploaded_file = UploaderWithCustomMetadata.upload(fakeio("file"), "store")

    uploaded_file.metadata.extra["custom"].should eq("value")
    uploaded_file.metadata.extra["first_bytes"].should eq("file")
    uploaded_file.metadata.extra["twice"].should eq("filefile")
  end

  it "sees the metadata found before it" do
    UploaderWithCustomMetadata.upload(image, "store").metadata.extra["seen_type"].should eq("image/png")
  end

  it "cannot set a built-in field" do
    uploaded_file = UploaderWithCustomMetadata.upload(fakeio("file"), "store")

    uploaded_file.size.should eq(4)
    uploaded_file.metadata.extra.has_key?("size").should be_false
  end

  it "adds nothing in the base uploader" do
    Gemma.upload(fakeio("file"), "store").metadata.extra.should be_empty
  end
end
