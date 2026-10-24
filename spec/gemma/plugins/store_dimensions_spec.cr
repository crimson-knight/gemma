require "../../spec_helper"
require "../../../src/gemma/plugins/store_dimensions"

class UploaderWithDimensions < Gemma::Uploader
  include Gemma::Plugins::StoreDimensions
end

class UploaderWithIdentify < Gemma::Uploader
  include Gemma::Plugins::StoreDimensions

  def self.dimensions_tool : Gemma::Plugins::StoreDimensions::Tools
    Gemma::Plugins::StoreDimensions::Tools::Identify
  end
end

describe Gemma::Plugins::StoreDimensions do
  before_each { reset_storages }

  describe "uploading" do
    it "stores width and height as integers" do
      uploaded_file = UploaderWithDimensions.upload(image("320x180.jpg"), "store")

      uploaded_file.width.should eq(320)
      uploaded_file.height.should eq(180)
    end

    it "stores a file that is not an image without dimensions" do
      uploaded_file = UploaderWithDimensions.upload(fakeio("not an image"), "store")

      uploaded_file.dimensions.should be_nil
      uploaded_file.exists?.should be_true
    end

    it "leaves the base uploader without dimensions" do
      Gemma.upload(image, "store").dimensions.should be_nil
    end
  end

  context "with the header analyzer" do
    it "extracts image dimensions" do
      UploaderWithDimensions.extract_dimensions(image).should eq({300, 300})
    end

    it "fails without image data" do
      expect_raises(Gemma::AnalyzerFailed) do
        UploaderWithDimensions.extract_dimensions(fakeio)
      end
    end
  end

  context "with the identify analyzer" do
    it "extracts image dimensions" do
      UploaderWithIdentify.extract_dimensions(image).should eq({300, 300})
      UploaderWithIdentify.extract_dimensions(fixture("progressive.jpg")).should eq({40, 30})
    end

    it "fails without image data" do
      expect_raises(Gemma::AnalyzerFailed) do
        UploaderWithIdentify.extract_dimensions(fakeio)
      end
    end

    it "stores an upload's dimensions" do
      UploaderWithIdentify.upload(fixture("lossy.webp"), "store").dimensions.should eq({40, 30})
    end
  end
end
