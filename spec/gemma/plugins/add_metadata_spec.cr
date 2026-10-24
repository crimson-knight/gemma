require "../../spec_helper"
require "../../../src/gemma/plugins/add_metadata"

class GemmaWithAddMetadata < Gemma
  load_plugin Gemma::Plugins::AddMetadata

  add_metadata :custom, -> {
    "value"
  }

  add_metadata :multiple_values, -> {
    text = io.gets_to_end

    {
      "custom_1" => text,
      "custom_2" => text * 2,
    }
  }

  add_metadata :spoofed_size, -> {
    {"size" => "1"}
  }

  finalize_plugins!
end

private def metadata_uploader : GemmaWithAddMetadata
  GemmaWithAddMetadata.new("store")
end

describe Gemma::Plugins::AddMetadata do
  before_each { reset_storages }

  it "adds a single declared value" do
    uploaded_file = metadata_uploader.upload(fakeio("file"))

    uploaded_file.metadata.extra["custom"].should eq("value")
  end

  it "adds a hash of values computed from the upload's bytes" do
    uploaded_file = metadata_uploader.upload(fakeio("file"))

    uploaded_file.metadata.extra["custom_1"].should eq("file")
    uploaded_file.metadata.extra["custom_2"].should eq("filefile")
  end

  it "cannot set a built-in field" do
    uploaded_file = metadata_uploader.upload(fakeio("file"))

    uploaded_file.size.should eq(4)
    uploaded_file.metadata.extra.has_key?("size").should be_false
  end
end
