require "../../spec_helper"
require "../../../src/gemma/plugins/add_metadata"

class GemmaWithAddMetadata < Gemma
  load_plugin Gemma::Plugins::AddMetadata

  # Makes Gemma#extract_metadata public for the specs.
  def extract_metadata(io : IO, **options) : Gemma::UploadedFile::MetadataType
    super
  end

  add_metadata :custom, -> {
    "value"
  }

  add_metadata :multiple_values, -> {
    text = io.gets_to_end

    Gemma::UploadedFile::MetadataType{
      "custom_1" => text,
      "custom_2" => text * 2,
    }
  }

  finalize_plugins!
end

private def metadata_uploader : GemmaWithAddMetadata
  GemmaWithAddMetadata.new("store")
end

describe Gemma::Plugins::AddMetadata do
  describe "Gemma.add_metadata" do
    context "with a single value" do
      it "adds declared metadata" do
        metadata = metadata_uploader.extract_metadata(fakeio)

        metadata["custom"].should eq("value")
        metadata["size"].should be_a(Int32)
      end

      it "adds the metadata to the UploadedFile" do
        uploaded_file = metadata_uploader.upload(fakeio)

        uploaded_file.metadata["custom"].should eq("value")
      end
    end

    context "with a hash of values" do
      it "adds declared metadata" do
        metadata = metadata_uploader.extract_metadata(fakeio)

        metadata["custom_1"].should eq(fakeio.gets_to_end)
        metadata["custom_2"].should eq(fakeio.gets_to_end * 2)
        metadata["size"].should be_a(Int32)
      end

      it "adds the metadata to the UploadedFile" do
        uploaded_file = metadata_uploader.upload(fakeio)

        uploaded_file.metadata["custom_1"].should eq(fakeio.gets_to_end)
        uploaded_file.metadata["custom_2"].should eq(fakeio.gets_to_end * 2)
      end
    end
  end
end
