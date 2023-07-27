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

  # redefine Gemma#extract_metadata to make it public
  def extract_metadata(io : IO, **options) : Gemma::UploadedFile::MetadataType
    super
  end

  finalize_plugins!
end

Spectator.describe Gemma::Plugins::StoreDimensions do
  include FileHelpers

  describe "primary purpose" do
    let(uploader) {
      GemmaWithStoreDimensionsUsingFastImage.new("store")
    }

    it "stores width and height in metadata" do
      metadata = uploader.extract_metadata(image("320x180.jpg"))

      expect(metadata["width"]).to eq(320)
      expect(metadata["height"]).to eq(180)
    end
  end

  describe "fastimage in analyzer" do
    subject { GemmaWithStoreDimensionsUsingFastImage }

    it "extracts image dimensions" do
      expect(subject.extract_dimensions(image)).to eq({300, 300})
    end

    it "fails with missing image data" do
      expect_raises(Gemma::Error) do
        subject.extract_dimensions(fakeio)
      end
    end
  end

  describe "identify analyzer" do
    subject { GemmaWithStoreDimensionsUsingIdentify }

    it "extracts image dimensions" do
      expect(subject.extract_dimensions(image)).to eq({300, 300})
    end

    it "fails with missing image data" do
      expect_raises(Gemma::Error) do
        subject.extract_dimensions(fakeio)
      end
    end
  end
end
