require "../spec_helper"

# followup-10-evidence/dims_probe.cr: an uploader with StoreDimensions
# returned the base `Gemma::UploadedFile`, and the plugin's typed `width`
# reader did not compile.
describe "dims probe" do
  it_reproduces_known_defect "gives an uploader's files a typed width and height", fixed_in: "PR 6 (Gemma::Uploader and plugin modules)" do
    result = SnippetCompiler.check <<-CRYSTAL
      require "gemma"

      class AvatarUploader < Gemma::Uploader
        include Gemma::Plugins::StoreDimensions
      end

      Gemma.configure { |config| config.storages["store"] = Gemma::Storage::Memory.new }
      file = AvatarUploader.upload(File.open("spec/support/300x300.png"), "store")
      width : Int32? = file.metadata.width
      height : Int32? = file.metadata.height
      CRYSTAL

    result.should_succeed
  end
end
