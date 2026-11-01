require "../../spec_helper"
require "../../../src/gemma/plugins/store_dimensions"

class GemmaWithStoreDimensionsUsingIdentify < Gemma
  load_plugin(Gemma::Plugins::StoreDimensions,
    analyzer: Gemma::Plugins::StoreDimensions::Tools::Identify)

  finalize_plugins!
end

class GemmaWithStoreDimensionsUsingFastImage < Gemma
  load_plugin(Gemma::Plugins::StoreDimensions,
    analyzer: Gemma::Plugins::StoreDimensions::Tools::FastImage)

  # Makes Gemma#extract_metadata public for the specs.
  def extract_metadata(io : IO, **options) : Gemma::UploadedFile::MetadataType
    super
  end

  finalize_plugins!
end

describe Gemma::Plugins::StoreDimensions do
  before_each { reset_storages }

  describe "#extract_metadata" do
    it "stores width and height in metadata" do
      metadata = GemmaWithStoreDimensionsUsingFastImage.new("store").extract_metadata(image("320x180.jpg"))

      metadata["width"].should eq(320)
      metadata["height"].should eq(180)
    end
  end

  context "with the fastimage analyzer" do
    it "extracts image dimensions" do
      GemmaWithStoreDimensionsUsingFastImage.extract_dimensions(image).should eq({300, 300})
    end

    it "fails with missing image data" do
      expect_raises(Gemma::AnalyzerFailed) do
        GemmaWithStoreDimensionsUsingFastImage.extract_dimensions(fakeio)
      end
    end
  end

  context "with the identify analyzer" do
    it "extracts image dimensions" do
      GemmaWithStoreDimensionsUsingIdentify.extract_dimensions(image).should eq({300, 300})
    end

    it "fails with missing image data" do
      expect_raises(Gemma::AnalyzerFailed) do
        GemmaWithStoreDimensionsUsingIdentify.extract_dimensions(fakeio)
      end
    end
  end
end
