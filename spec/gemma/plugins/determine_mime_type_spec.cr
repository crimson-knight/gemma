require "../../spec_helper"
require "../../../src/gemma/plugins/determine_mime_type"

class GemmaWithDetermineMimeTypeFile < Gemma
  load_plugin(Gemma::Plugins::DetermineMimeType,
    analyzer: Gemma::Plugins::DetermineMimeType::Tools::File)

  finalize_plugins!
end

class GemmaWithDetermineMimeTypeMime < Gemma
  load_plugin(Gemma::Plugins::DetermineMimeType,
    analyzer: Gemma::Plugins::DetermineMimeType::Tools::Mime)

  finalize_plugins!
end

describe Gemma::Plugins::DetermineMimeType do
  context "with the file analyzer" do
    describe ".determine_mime_type" do
      it "determines MIME type from file contents" do
        GemmaWithDetermineMimeTypeFile.determine_mime_type(image).should eq("image/png")
      end

      it "returns text/plain for unidentified MIME types" do
        GemmaWithDetermineMimeTypeFile.determine_mime_type(fakeio("a" * 1024)).should eq("text/plain")
      end

      it "is able to determine MIME type for non-files" do
        GemmaWithDetermineMimeTypeFile.determine_mime_type(fakeio(image.gets_to_end)).should eq("image/png")
      end

      it "returns nil for empty IOs" do
        GemmaWithDetermineMimeTypeFile.determine_mime_type(fakeio("")).should be_nil
      end
    end
  end

  context "with the mime analyzer" do
    describe ".determine_mime_type" do
      it "extracts MIME type from the file extension" do
        GemmaWithDetermineMimeTypeMime.determine_mime_type(fakeio(filename: "image.png")).should eq("image/png")
        GemmaWithDetermineMimeTypeMime.determine_mime_type(image).should eq("image/png")
      end

      it "extracts MIME type from file extension when IO is empty" do
        GemmaWithDetermineMimeTypeMime.determine_mime_type(fakeio("", filename: "image.png")).should eq("image/png")
      end

      it "returns nil on unknown extension" do
        GemmaWithDetermineMimeTypeMime.determine_mime_type(fakeio(filename: "image.foo")).should be_nil
      end

      it "returns nil when input is not a file" do
        GemmaWithDetermineMimeTypeMime.determine_mime_type(fakeio).should be_nil
      end
    end
  end
end
