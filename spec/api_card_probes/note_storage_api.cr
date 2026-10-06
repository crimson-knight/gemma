require "../../src/gemma"

Gemma.configure do |config|
  config.storages["cache"] = Gemma::Storage::Memory.new
  config.storages["store"] = Gemma::Storage::Memory.new
end

storage : Gemma::Storage::Base = Gemma.find_storage("store")
uploaded_file : Gemma::UploadedFile = Gemma.upload(IO::Memory.new("content"), "store")
opened_file : IO = storage.open("content")
file_url : String = storage.url("content")
file_exists : Bool = storage.exists?("content")
storage.delete("content")
