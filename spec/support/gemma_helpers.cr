module GemmaHelpers
  # def gemma
  #   uploader_class = Gemma

  #   uploader_class.settings.storages["cache"] = Gemma::Storage::Memory.new
  #   uploader_class.settings.storages["store"] = Gemma::Storage::Memory.new

  #   uploader_class
  # end

  def uploader(storage_key = "store")
    Gemma.new(storage_key)
  end
end
