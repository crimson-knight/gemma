require "../spec_helper"

private AMBER_UPLOAD_SNIPPET = <<-CRYSTAL
  require "gemma"

  # The shape of Amber::Router::File: a tempfile named <random><original>
  # plus the original filename and the part's headers.
  class AmberUploadDouble
    getter file : File = File.tempfile("photo.jpg")
    getter filename : String? = "photo.jpg"
    getter headers : HTTP::Headers = HTTP::Headers{"Content-Type" => "image/jpeg"}
  end

  Gemma.configure { |config| config.storages["store"] = Gemma::Storage::Memory.new }
  uploaded = Gemma.upload(AmberUploadDouble.new, "store")
  exit(uploaded.metadata.filename == "photo.jpg" ? 0 : 1)
  CRYSTAL

# followup-10-evidence/fs_promote_probe.cr: promotion between FileSystem
# storages wrote the object's `inspect` string, a `location:` escaped the
# root, and `upload` closed the caller's file.
describe "fs_promote probe" do
  it_reproduces_known_defect "promotes a FileSystem cache file to FileSystem store byte for byte", fixed_in: "PR 4 (IO-only storages)" do
    with_file_system_storages do |_root|
      content = Random::Secure.random_bytes(2 * 1024 * 1024)
      attacher = Gemma::Attacher.new
      attacher.attach_cached(IO::Memory.new(content))
      attacher.promote

      stored = attacher.file || fail("expected a promoted file")
      stored.storage_key.should eq("store")
      stored.open(&.getb_to_end).should eq(content)
    end
  end

  it_reproduces_known_defect "refuses a location that climbs out of the storage root", fixed_in: "PR 4 (storage containment)" do
    with_file_system_storages do |root|
      escaped_name = "escaped-#{Random::Secure.hex(4)}.txt"
      escaped_path = File.expand_path(File.join(root, "store", "../..", escaped_name))
      begin
        expect_raises(Gemma::Error) do
          Gemma.upload(IO::Memory.new("pwn"), "store", location: "../../#{escaped_name}")
        end
        File.exists?(escaped_path).should be_false
      ensure
        # While the defect is open the upload lands outside the root.
        File.delete?(escaped_path)
      end
    end
  end

  it_reproduces_known_defect "leaves the caller's file open after upload", fixed_in: "PR 4 (IO-only storages)" do
    with_file_system_storages do |_root|
      file = tempfile("x", "photo.jpg")
      begin
        Gemma.upload(file, "store")

        file.closed?.should be_false
      ensure
        file.close
        File.delete(file.path)
      end
    end
  end

  it_reproduces_known_defect "keeps the client's filename for an Amber-style upload", fixed_in: "PR 5 (upload objects)" do
    # A snippet, because passing the upload object itself does not compile
    # until Gemma accepts it.
    result = SnippetCompiler.check(AMBER_UPLOAD_SNIPPET)
    result.should_succeed

    # Compiling is not enough: the stored metadata must name the original.
    SnippetCompiler.run(AMBER_UPLOAD_SNIPPET).exit_code.should eq(0)
  end
end
