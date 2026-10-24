require "../../spec_helper"
require "../../../src/gemma/plugins/store_dimensions"

class GemmaWithStoreDimensions < Gemma
  load_plugin Gemma::Plugins::StoreDimensions

  finalize_plugins!
end

class GemmaWithStoreDimensionsUsingIdentify < Gemma
  load_plugin(Gemma::Plugins::StoreDimensions,
    analyzer: Gemma::Plugins::StoreDimensions::Tools::Identify)

  finalize_plugins!
end

describe Gemma::Plugins::StoreDimensions do
  before_each { reset_storages }

  describe "uploading" do
    it "stores width and height as integers" do
      uploaded_file = GemmaWithStoreDimensions.new("store").upload(image("320x180.jpg"))

      uploaded_file.width.should eq(320)
      uploaded_file.height.should eq(180)
      uploaded_file.metadata.width.should be_a(Int32?)
    end

    it "stores a file that is not an image without dimensions" do
      uploaded_file = GemmaWithStoreDimensions.new("store").upload(fakeio("not an image"))

      uploaded_file.dimensions.should be_nil
      uploaded_file.exists?.should be_true
    end
  end

  context "with the header analyzer" do
    it "extracts image dimensions" do
      GemmaWithStoreDimensions.extract_dimensions(image).should eq({300, 300})
    end

    it "fails without image data" do
      expect_raises(Gemma::AnalyzerFailed) do
        GemmaWithStoreDimensions.extract_dimensions(fakeio)
      end
    end
  end

  context "with the identify analyzer" do
    it "extracts image dimensions" do
      GemmaWithStoreDimensionsUsingIdentify.extract_dimensions(image).should eq({300, 300})
      GemmaWithStoreDimensionsUsingIdentify.extract_dimensions(fixture("progressive.jpg")).should eq({40, 30})
    end

    it "fails without image data" do
      expect_raises(Gemma::AnalyzerFailed) do
        GemmaWithStoreDimensionsUsingIdentify.extract_dimensions(fakeio)
      end
    end

    it "stores an upload's dimensions" do
      GemmaWithStoreDimensionsUsingIdentify.new("store").upload(fixture("lossy.webp")).dimensions.should eq({40, 30})
    end
  end
end
