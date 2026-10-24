require "../../spec_helper"

# Each fixture is a real file made by ImageMagick, cwebp, ffmpeg or zip.
MAGIC_BYTES_FIXTURES = {
  "baseline.jpg"    => "image/jpeg",
  "progressive.jpg" => "image/jpeg",
  "small.png"       => "image/png",
  "small.gif"       => "image/gif",
  "lossy.webp"      => "image/webp",
  "lossless.webp"   => "image/webp",
  "extended.webp"   => "image/webp",
  "small.bmp"       => "image/bmp",
  "small.tiff"      => "image/tiff",
  "small.heic"      => "image/heic",
  "small.avif"      => "image/avif",
  "small.svg"       => "image/svg+xml",
  "small.pdf"       => "application/pdf",
  "small.mp3"       => "audio/mpeg",
  "bare-frames.mp3" => "audio/mpeg",
  "small.m4a"       => "audio/mp4",
  "small.wav"       => "audio/wav",
  "small.flac"      => "audio/flac",
  "small.ogg"       => "audio/ogg",
  "small.mp4"       => "video/mp4",
  "small.mov"       => "video/quicktime",
  "small.webm"      => "video/webm",
  "small.zip"       => "application/zip",
  "small.txt"       => "text/plain",
}

describe Gemma::Analyzers::MagicBytes do
  describe ".mime_type" do
    MAGIC_BYTES_FIXTURES.each do |basename, mime_type|
      it "detects #{mime_type} in #{basename}" do
        Gemma::Analyzers::MagicBytes.mime_type(fixture_bytes(basename)).should eq(mime_type)
      end
    end

    it "gives nil for bytes it does not recognize" do
      Gemma::Analyzers::MagicBytes.mime_type(fixture_bytes("unknown.bin")).should be_nil
    end

    it "gives nil for no bytes" do
      Gemma::Analyzers::MagicBytes.mime_type(Bytes.empty).should be_nil
    end

    it "reads HTML as plain text, so it is never served as a page" do
      Gemma::Analyzers::MagicBytes.mime_type("<html><script>alert(1)</script></html>".to_slice).should eq("text/plain")
    end

    it "counts text cut off in the middle of a UTF-8 character as text" do
      Gemma::Analyzers::MagicBytes.mime_type("café".to_slice[0, 4]).should eq("text/plain")
    end
  end

  describe ".extension_for" do
    it "gives the canonical extension" do
      Gemma::Analyzers::MagicBytes.extension_for("image/jpeg").should eq("jpg")
      Gemma::Analyzers::MagicBytes.extension_for("application/x-unknown").should be_nil
    end
  end

  describe ".extension_matches?" do
    it "accepts the usual extensions of a type in any case" do
      Gemma::Analyzers::MagicBytes.extension_matches?("JPEG", "image/jpeg").should be_true
      Gemma::Analyzers::MagicBytes.extension_matches?("html", "text/plain").should be_false
    end
  end
end
