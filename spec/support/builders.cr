require "file_utils"
require "./fake_io"

# Builders shared by the specs. Each returns a fresh object, so examples never
# share state through them.

SPEC_SUPPORT_DIRECTORY = File.expand_path(__DIR__)

def fakeio(content : String = "file", filename : String? = nil, content_type : String? = nil) : FakeIO
  FakeIO.new(content, filename: filename, content_type: content_type)
end

# Writes *content* to a new temporary file and returns it opened for reading.
def tempfile(content : String, basename : String = "") : File
  path = File.tempfile(basename, &.print(content)).path
  File.open(path)
end

def image(basename : String = "300x300.png") : File
  File.open(File.join(SPEC_SUPPORT_DIRECTORY, basename))
end

def uploader(storage_key : String = "store") : Gemma
  Gemma.new(storage_key)
end

def memory_storage(storage_key : String) : Gemma::Storage::Memory
  Gemma.settings.storages[storage_key].as(Gemma::Storage::Memory)
end

# Points every spec storage at a fresh `Memory` storage.
def reset_storages : Nil
  Gemma.configure do |config|
    {"cache", "store", "other_cache", "other_store"}.each do |storage_key|
      config.storages[storage_key] = Gemma::Storage::Memory.new
    end
  end
end

def file_permissions(path : String) : Int32
  File.info(path).permissions.value.to_i32
end

# Returns a new, empty directory under the system temp directory.
def temporary_root : String
  File.join(Dir.tempdir, "gemma-spec-#{Random::Secure.hex(8)}")
end
