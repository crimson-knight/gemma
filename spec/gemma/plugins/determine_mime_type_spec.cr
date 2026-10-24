require "../../spec_helper"
require "../../../src/gemma/plugins/determine_mime_type"

class UploaderWithFileCommand < Gemma::Uploader
  include Gemma::Plugins::DetermineMimeType

  def self.mime_type_tool : Gemma::Plugins::DetermineMimeType::Tools
    Gemma::Plugins::DetermineMimeType::Tools::File
  end
end

class UploaderWithFilenameMime < Gemma::Uploader
  include Gemma::Plugins::DetermineMimeType

  def self.mime_type_tool : Gemma::Plugins::DetermineMimeType::Tools
    Gemma::Plugins::DetermineMimeType::Tools::Mime
  end
end

class UploaderWithDeclaredContentType < Gemma::Uploader
  include Gemma::Plugins::DetermineMimeType

  def self.mime_type_tool : Gemma::Plugins::DetermineMimeType::Tools
    Gemma::Plugins::DetermineMimeType::Tools::ContentType
  end
end

class UploaderWithDefaultMimeTool < Gemma::Uploader
  include Gemma::Plugins::DetermineMimeType
end

describe Gemma::Plugins::DetermineMimeType do
  before_each { reset_storages }

  context "with the default analyzer" do
    it "uses the built-in sniffer" do
      UploaderWithDefaultMimeTool.determine_mime_type(image).should eq("image/png")
      UploaderWithDefaultMimeTool.determine_mime_type(fakeio("", filename: "a.png")).should be_nil
    end
  end

  context "with the file analyzer" do
    it "determines the MIME type from the content" do
      UploaderWithFileCommand.determine_mime_type(image).should eq("image/png")
    end

    it "reads a non-file IO" do
      UploaderWithFileCommand.determine_mime_type(fakeio(image.gets_to_end)).should eq("image/png")
    end

    it "returns text/plain for text" do
      UploaderWithFileCommand.determine_mime_type(fakeio("a" * 1024)).should eq("text/plain")
    end

    it "returns nil for an empty IO" do
      UploaderWithFileCommand.determine_mime_type(fakeio("")).should be_nil
    end

    it "is used for uploads" do
      UploaderWithFileCommand.upload(image, "store").mime_type.should eq("image/png")
    end
  end

  context "with the mime analyzer" do
    it "uses the filename's extension for bytes the sniffer does not recognize" do
      UploaderWithFilenameMime.determine_mime_type(fakeio("\u0000\u0001", filename: "data.csv")).should eq("text/csv")
      UploaderWithFilenameMime.determine_mime_type(fakeio("", filename: "image.png")).should eq("image/png")
    end

    it "prefers the sniffed type when the bytes are recognized" do
      UploaderWithFilenameMime.determine_mime_type(fakeio(image.gets_to_end, filename: "photo.jpg")).should eq("image/png")
    end

    it "returns nil on an unknown extension or no filename" do
      UploaderWithFilenameMime.determine_mime_type(fakeio("\u0000", filename: "image.foo")).should be_nil
      UploaderWithFilenameMime.determine_mime_type(fakeio("\u0000")).should be_nil
    end

    it "never claims a type a browser runs" do
      UploaderWithFilenameMime.determine_mime_type(fakeio("\u0000<script>", filename: "page.html")).should eq("application/octet-stream")
    end
  end

  context "with the content type analyzer" do
    it "uses the declared Content-Type for bytes the sniffer does not recognize" do
      UploaderWithDeclaredContentType.determine_mime_type(fakeio("\u0000", content_type: "application/x-custom; charset=binary")).should eq("application/x-custom")
    end

    it "prefers the sniffed type and refuses active content" do
      UploaderWithDeclaredContentType.determine_mime_type(fakeio("text", content_type: "image/png")).should eq("text/plain")
      UploaderWithDeclaredContentType.determine_mime_type(fakeio("\u0000", content_type: "image/svg+xml")).should eq("application/octet-stream")
    end

    it "reads the declared type from an upload" do
      uploaded = UploaderWithDeclaredContentType.upload(fakeio("\u0000"), "store", declared_content_type: "application/x-custom")

      uploaded.mime_type.should eq("application/x-custom")
    end
  end
end
