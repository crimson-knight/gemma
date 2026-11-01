require "../spec_helper"

private class SettingsSpecUploader < Gemma
end

describe Gemma::Settings do
  describe "Gemma.configure" do
    it "yields the settings that Gemma.settings returns" do
      yielded_settings = nil
      Gemma.configure { |config| yielded_settings = config }

      yielded_settings.should be(Gemma.settings)
    end
  end

  describe "uploader subclasses" do
    it "share Gemma's storages" do
      SettingsSpecUploader.settings.should be(Gemma.settings)
      SettingsSpecUploader.find_storage("store").should be(Gemma.settings.storages["store"])
    end
  end
end
