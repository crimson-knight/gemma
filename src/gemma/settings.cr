class Gemma
  # Holds Gemma's configuration. Apps change it in `Gemma.configure`, usually
  # from `config/initializers/gemma.cr`.
  class Settings
    # Storages by name, e.g. `"cache"` and `"store"`.
    property storages : Hash(String, Storage::Base) = Hash(String, Storage::Base).new
  end

  # The one settings object shared by `Gemma` and every uploader subclass.
  SETTINGS = Settings.new
end
