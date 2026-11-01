# Yields after pointing "cache" and "store" at FileSystem storages under a
# fresh root, then restores Memory storages and removes the root.
def with_file_system_storages(& : String ->)
  root = temporary_root
  Gemma.configure do |config|
    config.storages["cache"] = Gemma::Storage::FileSystem.new(root, prefix: "cache")
    config.storages["store"] = Gemma::Storage::FileSystem.new(root, prefix: "store")
  end
  begin
    yield root
  ensure
    reset_storages
    FileUtils.rm_rf(root)
  end
end
