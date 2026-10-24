require "../../spec_helper"

describe Gemma::Analyzers::ImageDimensions do
  describe ".dimensions" do
    it "reads the dimensions fastimage read from the original fixtures" do
      Gemma::Analyzers::ImageDimensions.dimensions(File.read(File.join(SPEC_SUPPORT_DIRECTORY, "300x300.png")).to_slice).should eq({300, 300})
      Gemma::Analyzers::ImageDimensions.dimensions(File.read(File.join(SPEC_SUPPORT_DIRECTORY, "320x180.jpg")).to_slice).should eq({320, 180})
    end

    {"baseline.jpg", "progressive.jpg", "large-comment.jpg", "small.png", "small.gif", "small.bmp", "lossy.webp", "lossless.webp", "extended.webp"}.each do |basename|
      it "reads 40x30 from #{basename}" do
        Gemma::Analyzers::ImageDimensions.dimensions(fixture_bytes(basename)).should eq({40, 30})
      end
    end

    it "finds a JPEG frame header after a 60 KB comment segment" do
      bytes = fixture_bytes("large-comment.jpg")
      bytes.size.should be > 60_000

      Gemma::Analyzers::ImageDimensions.dimensions(bytes).should eq({40, 30})
    end

    it "gives nil for a header cut off before the dimensions" do
      Gemma::Analyzers::ImageDimensions.dimensions(fixture_bytes("small.png")[0, 20]).should be_nil
      Gemma::Analyzers::ImageDimensions.dimensions(fixture_bytes("large-comment.jpg")[0, 1000]).should be_nil
    end

    it "gives nil for a JPEG frame header shorter than its fields" do
      Gemma::Analyzers::ImageDimensions.dimensions(Bytes[0xFF, 0xD8, 0xFF, 0xC0, 0x00, 0x02, 0x08, 0x00, 0x1E, 0x00, 0x28]).should be_nil
    end

    it "gives nil for files that are not images it reads" do
      Gemma::Analyzers::ImageDimensions.dimensions(fixture_bytes("small.pdf")).should be_nil
      Gemma::Analyzers::ImageDimensions.dimensions(fixture_bytes("small.tiff")).should be_nil
      Gemma::Analyzers::ImageDimensions.dimensions(Bytes.empty).should be_nil
    end
  end
end
