require "../spec_helper"
require "../../src/gemma/plugins/determine_mime_type"

private class ErrProbeFileCommandUploader < Gemma
  load_plugin(Gemma::Plugins::DetermineMimeType,
    analyzer: Gemma::Plugins::DetermineMimeType::Tools::File)

  finalize_plugins!
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
  it_reproduces_known_defect "raises Gemma::FileNotFound when FileSystem#open misses", fixed_in: "PR 3 (error types)" do
    root = temporary_root
    begin
      storage = Gemma::Storage::FileSystem.new(root)
      expect_raises(Gemma::FileNotFound) { storage.open("missing") }
    ensure
      FileUtils.rm_rf(root)
    end
  end

  it_reproduces_known_defect "raises a Gemma::Error when an analyzer's command is not installed", fixed_in: "PR 3 (error types)" do
    without_executables do
      expect_raises(Gemma::Error) do
        ErrProbeFileCommandUploader.determine_mime_type(fakeio("text"))
      end
    end
  end

  it "raises Gemma::Error for a storage that is not registered" do
    expect_raises(Gemma::Error, %(storage "nope" isn't registered)) do
      Gemma::UploadedFile.new("x", "nope").url
    end
  end
end
