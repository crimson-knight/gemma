require "../../spec_helper"

private def file_system_storage(root : String, prefix : String? = nil, permissions : Int32 = Gemma::Storage::FileSystem::DEFAULT_PERMISSIONS, directory_permissions : Int32 = Gemma::Storage::FileSystem::DEFAULT_DIRECTORY_PERMISSIONS) : Gemma::Storage::FileSystem
  Gemma::Storage::FileSystem.new(
    directory: root,
    prefix: prefix,
    permissions: permissions,
    directory_permissions: directory_permissions
  )
end

# Yields a fresh storage root and removes it afterwards.
private def with_root(&)
  root = temporary_root
  begin
    yield root
  ensure
    FileUtils.rm_rf(root)
  end
end

describe Gemma::Storage::FileSystem do
  describe "#initialize" do
    context "without a prefix" do
      it "expands the directory" do
        with_root do |root|
          file_system_storage(root).expanded_directory.should eq(File.expand_path(root))
        end
      end

      it "creates the given directory" do
        with_root do |root|
          File.directory?(file_system_storage(root).expanded_directory).should be_true
        end
      end
    end

    context "with a prefix" do
      it "expands the directory" do
        with_root do |root|
          file_system_storage(root, prefix: "prefix").expanded_directory.should eq(File.expand_path(File.join(root, "prefix")))
        end
      end

      it "creates the given directory" do
        with_root do |root|
          File.directory?(file_system_storage(root, prefix: "prefix").expanded_directory).should be_true
        end
      end
    end

    it "sets the default directory permissions" do
      with_root do |root|
        file_permissions(file_system_storage(root).expanded_directory).should eq(Gemma::Storage::FileSystem::DEFAULT_DIRECTORY_PERMISSIONS)
      end
    end

    it "sets 0o500 directory permissions" do
      with_root do |root|
        file_permissions(file_system_storage(root, directory_permissions: 0o500).expanded_directory).should eq(0o500)
      end
    end
  end

  describe "#upload" do
    it "creates subdirectories" do
      with_root do |root|
        storage = file_system_storage(root)
        storage.upload(FakeIO.new, "a/a/a.jpg")

        storage.exists?("a/a/a.jpg").should be_true
      end
    end

    it "copies the full file content" do
      with_root do |root|
        storage = file_system_storage(root)
        storage.upload(FakeIO.new("A" * 20_000), "foo.jpg")

        storage.open("foo.jpg").size.should eq(20_000)
      end
    end

    it "sets 0o600 file permissions" do
      with_root do |root|
        storage = file_system_storage(root, permissions: 0o600)
        storage.upload(FakeIO.new, "foo.jpg")

        file_permissions(storage.open("foo.jpg").path).should eq(0o600)
      end
    end

    it "sets 0o744 directory permissions on intermediate directories" do
      with_root do |root|
        storage = file_system_storage(root, directory_permissions: 0o744)
        storage.upload(FakeIO.new, "a/b/c/file.jpg")

        file_permissions("#{storage.expanded_directory}/a").should eq(0o744)
        file_permissions("#{storage.expanded_directory}/a/b").should eq(0o744)
        file_permissions("#{storage.expanded_directory}/a/b/c").should eq(0o744)
      end
    end

    it "leaves the source IO open" do
      with_root do |root|
        source = tempfile("file")
        file_system_storage(root).upload(source, "foo.jpg")

        source.closed?.should be_false
        source.close
      end
    end

    it "refuses an id that climbs out of the directory and writes nothing" do
      with_root do |root|
        storage = file_system_storage(root, prefix: "store")

        expect_raises(Gemma::InvalidLocation) { storage.upload(fakeio("pwn"), "../escaped.txt") }
        File.exists?(File.join(root, "escaped.txt")).should be_false
      end
    end
  end

  describe "#open" do
    it "opens the stored file for reading" do
      with_root do |root|
        storage = file_system_storage(root)
        storage.upload(fakeio("content"), "foo.txt")

        storage.open("foo.txt").gets_to_end.should eq("content")
      end
    end

    it "raises Gemma::FileNotFound for a missing file" do
      with_root do |root|
        expect_raises(Gemma::FileNotFound) { file_system_storage(root).open("missing.txt") }
      end
    end

    it "refuses an id that climbs out of the directory" do
      with_root do |root|
        expect_raises(Gemma::InvalidLocation) { file_system_storage(root).open("../../../../etc/hosts") }
      end
    end
  end

  describe "#url" do
    it "returns the full path without a prefix" do
      with_root do |root|
        storage = file_system_storage(root)
        storage.upload(fakeio, "foo.jpg")

        storage.url("foo.jpg").should eq("#{storage.expanded_directory}/foo.jpg")
      end
    end

    it "applies a host without a prefix" do
      with_root do |root|
        storage = file_system_storage(root)
        storage.upload(fakeio, "foo.jpg")

        storage.url("foo.jpg", host: "http://124.83.12.24").should eq("http://124.83.12.24#{root}/foo.jpg")
      end
    end

    it "returns the path relative to the prefix" do
      with_root do |root|
        storage = file_system_storage(root, prefix: "prefix")
        storage.upload(fakeio, "foo.jpg")

        storage.url("foo.jpg").should eq("/prefix/foo.jpg")
      end
    end

    it "percent-encodes each segment, so a browser cannot turn %2e%2e into .." do
      with_root do |root|
        storage = file_system_storage(root, prefix: "cache")

        storage.url("%2e%2e/store/victim.jpg").should eq("/cache/%252e%252e/store/victim.jpg")
        storage.url("a b.jpg").should eq("/cache/a%20b.jpg")
      end
    end

    it "accepts a host with a prefix" do
      with_root do |root|
        storage = file_system_storage(root, prefix: "prefix")
        storage.upload(fakeio, "foo.jpg")

        storage.url("foo.jpg", host: "http://abc123.cloudfront.net").should eq("http://abc123.cloudfront.net/prefix/foo.jpg")
      end
    end
  end

  describe "#path" do
    it "returns the path to the file" do
      with_root do |root|
        file_system_storage(root).path("foo/bar/baz").should eq("#{root}/foo/bar/baz")
      end
    end

    it "refuses an id that reaches outside through a symlinked directory" do
      with_root do |root|
        outside = temporary_root
        Dir.mkdir_p(outside)
        File.write(File.join(outside, "secret.txt"), "secret")
        begin
          storage = file_system_storage(root, prefix: "cache")
          File.symlink(outside, File.join(storage.expanded_directory, "link"))

          expect_raises(Gemma::InvalidLocation) { storage.open("link/secret.txt") }
          expect_raises(Gemma::InvalidLocation) { storage.upload(fakeio("pwn"), "link/planted.txt") }
          expect_raises(Gemma::InvalidLocation) { storage.delete("link/secret.txt") }
          File.exists?(File.join(outside, "planted.txt")).should be_false
          File.exists?(File.join(outside, "secret.txt")).should be_true
        ensure
          FileUtils.rm_rf(outside)
        end
      end
    end

    it "refuses a symlinked file that points outside" do
      with_root do |root|
        storage = file_system_storage(root)
        File.symlink("/etc/hosts", File.join(storage.expanded_directory, "hosts"))

        expect_raises(Gemma::InvalidLocation) { storage.open("hosts") }
      end
    end

    it "keeps a path that goes up and back down inside the directory" do
      with_root do |root|
        file_system_storage(root).path("a/../b.txt").should eq("#{root}/b.txt")
      end
    end

    {"../outside.txt", "a/../../outside.txt", "/etc/hosts", "", ".", "a/\0b"}.each do |escaping_id|
      it "raises Gemma::InvalidLocation for #{escaping_id.inspect}" do
        with_root do |root|
          expect_raises(Gemma::InvalidLocation) { file_system_storage(root).path(escaping_id) }
        end
      end
    end
  end

  describe "#delete" do
    it "deletes the file and the directories it leaves empty, but never the storage directory" do
      with_root do |root|
        storage = file_system_storage(root, prefix: "store")
        storage.upload(fakeio, "a/b/file.txt")

        storage.delete("a/b/file.txt")

        storage.exists?("a/b/file.txt").should be_false
        Dir.exists?(File.join(storage.expanded_directory, "a")).should be_false
        Dir.exists?(storage.expanded_directory).should be_true
      end
    end

    it "keeps a directory that still holds other files" do
      with_root do |root|
        storage = file_system_storage(root)
        storage.upload(fakeio, "a/one.txt")
        storage.upload(fakeio, "a/two.txt")

        storage.delete("a/one.txt")

        storage.exists?("a/two.txt").should be_true
      end
    end

    it "does nothing for a missing file" do
      with_root do |root|
        file_system_storage(root).delete("missing.txt")
      end
    end
  end
end
