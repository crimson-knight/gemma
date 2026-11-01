require "../spec_helper"
require "../../src/gemma/plugins/store_dimensions"

private SNIPPET_PREFIX = <<-CRYSTAL
  require "gemma"
  require "gemma/plugins/store_dimensions"
  require "gemma/plugins/add_metadata"
  require "gemma/plugins/column"

  CRYSTAL

private class PluginsSpecUploader < Gemma::Uploader
  include Gemma::Plugins::StoreDimensions
end

describe "Gemma plugins" do
  before_each { reset_storages }

  it "are modules an uploader subclass includes" do
    PluginsSpecUploader.new("store").is_a?(Gemma::Plugins::StoreDimensions).should be_true
    Gemma::Uploader.new("store").is_a?(Gemma::Plugins::StoreDimensions).should be_false
  end

  it "give each uploader its own attacher" do
    PluginsSpecUploader::Attacher.uploader_class.should eq(PluginsSpecUploader)
    Gemma::Attacher.uploader_class.should eq(Gemma::Uploader)

    attacher = PluginsSpecUploader::Attacher.new
    attacher.attach(image)
    attacher.file.try(&.width).should eq(300)
  end

  describe "the removed load_plugin API" do
    it "names the module to include" do
      result = SnippetCompiler.check(SNIPPET_PREFIX + <<-CRYSTAL)
        class AvatarUploader < Gemma::Uploader
          load_plugin Gemma::Plugins::StoreDimensions
        end
        CRYSTAL

      result.should_fail_with("include Gemma::Plugins::StoreDimensions")
    end

    it "names the custom_metadata method for AddMetadata" do
      result = SnippetCompiler.check(SNIPPET_PREFIX + <<-CRYSTAL)
        class DocumentUploader < Gemma::Uploader
          load_plugin Gemma::Plugins::AddMetadata
        end
        CRYSTAL

      result.should_fail_with("def custom_metadata(io : IO, metadata : Gemma::Metadata)")
    end

    it "explains that finalize_plugins! has nothing left to do" do
      result = SnippetCompiler.check(SNIPPET_PREFIX + <<-CRYSTAL)
        class DocumentUploader < Gemma::Uploader
          finalize_plugins!
        end
        CRYSTAL

      result.should_fail_with("Delete the call")
    end

    it "explains that the Column plugin is built in" do
      result = SnippetCompiler.check(SNIPPET_PREFIX + <<-CRYSTAL)
        class DocumentUploader < Gemma::Uploader
          include Gemma::Plugins::Column
        end
        CRYSTAL

      result.should_fail_with("Attacher.from_column")
    end
  end
end
