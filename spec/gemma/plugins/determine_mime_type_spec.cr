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

class GemmaWithDetermineMimeTypeContentType < Gemma
  load_plugin(Gemma::Plugins::DetermineMimeType,
    analyzer: Gemma::Plugins::DetermineMimeType::Tools::ContentType)

  finalize_plugins!
end

class GemmaWithDetermineMimeTypeDefault < Gemma
  load_plugin Gemma::Plugins::DetermineMimeType

  finalize_plugins!
end

describe Gemma::Plugins::DetermineMimeType do
  before_each { reset_storages }

  context "with the default analyzer" do
    it "uses the built-in sniffer" do
      GemmaWithDetermineMimeTypeDefault.determine_mime_type(image).should eq("image/png")
      GemmaWithDetermineMimeTypeDefault.determine_mime_type(fakeio("", filename: "a.png")).should be_nil
    end
  end

  context "with the file analyzer" do
    it "determines the MIME type from the content" do
      GemmaWithDetermineMimeTypeFile.determine_mime_type(image).should eq("image/png")
    end

    it "reads a non-file IO" do
      GemmaWithDetermineMimeTypeFile.determine_mime_type(fakeio(image.gets_to_end)).should eq("image/png")
    end

    it "returns text/plain for text" do
      GemmaWithDetermineMimeTypeFile.determine_mime_type(fakeio("a" * 1024)).should eq("text/plain")
    end

    it "returns nil for an empty IO" do
      GemmaWithDetermineMimeTypeFile.determine_mime_type(fakeio("")).should be_nil
    end

    it "is used for uploads" do
      GemmaWithDetermineMimeTypeFile.new("store").upload(image).mime_type.should eq("image/png")
    end
  end

  context "with the mime analyzer" do
    it "uses the filename's extension for bytes the sniffer does not recognize" do
      GemmaWithDetermineMimeTypeMime.determine_mime_type(fakeio("\u0000\u0001", filename: "data.csv")).should eq("text/csv")
      GemmaWithDetermineMimeTypeMime.determine_mime_type(fakeio("", filename: "image.png")).should eq("image/png")
    end

    it "prefers the sniffed type when the bytes are recognized" do
      GemmaWithDetermineMimeTypeMime.determine_mime_type(fakeio(image.gets_to_end, filename: "photo.jpg")).should eq("image/png")
    end

    it "returns nil on an unknown extension or no filename" do
      GemmaWithDetermineMimeTypeMime.determine_mime_type(fakeio("\u0000", filename: "image.foo")).should be_nil
      GemmaWithDetermineMimeTypeMime.determine_mime_type(fakeio("\u0000")).should be_nil
    end

    it "never claims a type a browser runs" do
      GemmaWithDetermineMimeTypeMime.determine_mime_type(fakeio("\u0000<script>", filename: "page.html")).should eq("application/octet-stream")
    end
  end

  context "with the content type analyzer" do
    it "uses the declared Content-Type for bytes the sniffer does not recognize" do
      GemmaWithDetermineMimeTypeContentType.determine_mime_type(fakeio("\u0000", content_type: "application/x-custom; charset=binary")).should eq("application/x-custom")
    end

    it "prefers the sniffed type and refuses active content" do
      GemmaWithDetermineMimeTypeContentType.determine_mime_type(fakeio("text", content_type: "image/png")).should eq("text/plain")
      GemmaWithDetermineMimeTypeContentType.determine_mime_type(fakeio("\u0000", content_type: "image/svg+xml")).should eq("application/octet-stream")
    end

    it "reads the declared type from an upload" do
      uploaded = GemmaWithDetermineMimeTypeContentType.new("store").upload(fakeio("\u0000"), declared_content_type: "application/x-custom")

      uploaded.mime_type.should eq("application/x-custom")
    end
  end
end
