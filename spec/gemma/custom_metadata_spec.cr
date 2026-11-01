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

class UploaderMeasuringAspect < Gemma::Uploader
  include Gemma::Plugins::StoreDimensions

  def custom_metadata(io : IO, metadata : Gemma::Metadata) : Hash(String, String)
    fields = {} of String => String
    if dimensions = metadata.dimensions
      width, height = dimensions
      fields["aspect"] = (width / height).to_s
    end
    metadata.mime_type = "image/svg+xml"
    metadata.extra["leak"] = "x"
    fields
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

  it "sees the dimensions a plugin found" do
    UploaderMeasuringAspect.upload(image("320x180.jpg"), "store").metadata.extra["aspect"].should eq((320 / 180).to_s)
  end

  it "cannot change built-in fields or custom fields through the metadata it receives" do
    uploaded_file = UploaderMeasuringAspect.upload(image, "store")

    uploaded_file.mime_type.should eq("image/png")
    uploaded_file.metadata.extra.has_key?("leak").should be_false
  end

  it "applies to a verified cached reference as well" do
    cached = UploaderWithCustomMetadata.upload(fakeio("file"), "cache")
    attacher = UploaderWithCustomMetadata::Attacher.new
    attacher.attach_cached(Gemma::CachedFileReference.new(cached.id, "cache"))

    attacher.file.try(&.metadata.extra["custom"]?).should eq("value")
  end

  it "adds nothing in the base uploader" do
    Gemma.upload(fakeio("file"), "store").metadata.extra.should be_empty
  end
end
