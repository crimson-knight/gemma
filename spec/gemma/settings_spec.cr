require "../spec_helper"

private class SettingsSpecUploader < Gemma::Uploader
end

describe Gemma::Settings do
  describe "Gemma.configure" do
    it "yields the settings that Gemma.settings returns" do
      yielded_settings = nil
      Gemma.configure { |config| yielded_settings = config }

      yielded_settings.should be(Gemma.settings)
    end
  end

  describe "Gemma.find_storage" do
    it "raises Gemma::StorageNotRegistered for an unknown name" do
      expect_raises(Gemma::StorageNotRegistered) { Gemma.find_storage("nowhere") }
    end
  end

  describe "uploader subclasses" do
    it "share Gemma's storages" do
      SettingsSpecUploader.new("store").storage.should be(Gemma.settings.storages["store"])
    end
  end
end
