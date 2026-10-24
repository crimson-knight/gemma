require "../spec_helper"

# followup-10-evidence/dims_probe.cr: an uploader with StoreDimensions
# returned the base `Gemma::UploadedFile`, and the plugin's typed `width`
# reader did not compile.
describe "dims probe" do
  it "gives an uploader's files a typed width and height" do
    result = SnippetCompiler.run <<-CRYSTAL
      require "gemma"

      class AvatarUploader < Gemma::Uploader
        include Gemma::Plugins::StoreDimensions
      end

      Gemma.configure { |config| config.storages["store"] = Gemma::Storage::Memory.new }
      file = AvatarUploader.upload(File.open("spec/support/300x300.png"), "store")
      width : Int32? = file.metadata.width
      height : Int32? = file.metadata.height
      exit(width == 300 && height == 300 ? 0 : 1)
      CRYSTAL

    result.exit_code.should eq(0)
  end
end
