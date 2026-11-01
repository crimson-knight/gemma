require "../spec_helper"

private module FooPlugin
  module ClassMethods
    def foo
      "plugin_foo"
    end
  end

  module InstanceMethods
    def foo
      "plugin_foo"
    end
  end

  module FileClassMethods
    def foo
      "plugin_foo"
    end
  end

  module FileMethods
    def foo
      "plugin_foo"
    end
  end
end

private class NonPluginUploader < Gemma
  module ClassMethods
    def foo
      "foo"
    end
  end

  module InstanceMethods
    def foo
      "foo"
    end
  end

  extend ClassMethods
  include InstanceMethods
end

private class PluginUploader < NonPluginUploader
  load_plugin FooPlugin
  finalize_plugins!
end

describe "Gemma.load_plugin" do
  describe "an uploader without the plugin" do
    it "responds to .foo with \"foo\"" do
      NonPluginUploader.foo.should eq("foo")
    end

    it "responds to #foo with \"foo\"" do
      NonPluginUploader.new("store").foo.should eq("foo")
    end
  end

  describe "an uploader with the plugin" do
    it "responds to .foo with the plugin's value" do
      PluginUploader.foo.should eq("plugin_foo")
    end

    it "responds to #foo with the plugin's value" do
      PluginUploader.new("store").foo.should eq("plugin_foo")
    end
  end

  describe "the plugin uploader's UploadedFile" do
    it "responds to .foo with the plugin's value" do
      PluginUploader::UploadedFile.foo.should eq("plugin_foo")
    end

    it "does not add .foo to Gemma::UploadedFile" do
      Gemma::UploadedFile.responds_to?(:foo).should be_false
    end
  end
end
