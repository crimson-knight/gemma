require "../spec_helper"

private class SettingsSpecUploader < Gemma
end

Spectator.describe Gemma::Settings do
  describe "Gemma.configure" do
    it "yields the settings that Gemma.settings returns" do
      yielded_settings = nil
      Gemma.configure { |config| yielded_settings = config }

      expect(yielded_settings).to be(Gemma.settings)
    end
  end

  describe "uploader subclasses" do
    it "share Gemma's storages" do
      expect(SettingsSpecUploader.settings).to be(Gemma.settings)
      expect(SettingsSpecUploader.find_storage("store")).to be(Gemma.settings.storages["store"])
    end
  end
end
