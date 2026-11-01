require "../spec_helper"
require "../../src/gemma/plugins/determine_mime_type"

private class ErrProbeFileCommandUploader < Gemma::Uploader
  include Gemma::Plugins::DetermineMimeType

  def self.mime_type_tool : Gemma::Plugins::DetermineMimeType::Tools
    Gemma::Plugins::DetermineMimeType::Tools::File
  end
end

# Runs the block with an empty PATH, so no external command can be found.
private def without_executables(&)
  original_path = ENV["PATH"]?
  ENV["PATH"] = ""
  begin
    yield
  ensure
    ENV["PATH"] = original_path
  end
end

# followup-10-evidence/err_probe.cr: stdlib errors escaped where Gemma
# promised its own.
describe "err probe" do
  it "raises Gemma::FileNotFound when FileSystem#open misses" do
    root = temporary_root
    begin
      storage = Gemma::Storage::FileSystem.new(root)
      error = expect_raises(Gemma::FileNotFound) { storage.open("missing") }
      error.cause.should be_a(File::NotFoundError)
    ensure
      FileUtils.rm_rf(root)
    end
  end

  it "raises Gemma::AnalyzerMissing when an analyzer's command is not installed" do
    without_executables do
      error = expect_raises(Gemma::AnalyzerMissing) do
        ErrProbeFileCommandUploader.determine_mime_type(fakeio("text"))
      end
      error.cause.should be_a(File::NotFoundError)
    end
  end

  it "raises Gemma::Error for a storage that is not registered" do
    expect_raises(Gemma::StorageNotRegistered, %(storage "nope" isn't registered)) do
      Gemma::UploadedFile.new("x", "nope").url
    end
  end
end
