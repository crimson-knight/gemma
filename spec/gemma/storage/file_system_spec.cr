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

    context "with move: true" do
      it "moves movable files" do
        with_root do |root|
          storage = file_system_storage(root)
          file = tempfile("file")
          storage.upload(file, "foo", move: true)

          storage.open("foo").gets_to_end.should eq("file")
          File.exists?(file.path).should be_false
        end
      end

      it "creates subdirectories" do
        with_root do |root|
          storage = file_system_storage(root)
          storage.upload(tempfile("file"), "a/a/a.jpg", move: true)

          storage.exists?("a/a/a.jpg").should be_true
        end
      end

      it "sets 0o600 file permissions" do
        with_root do |root|
          storage = file_system_storage(root, permissions: 0o600)
          storage.upload(tempfile("file"), "bar.jpg", move: true)

          file_permissions(storage.open("bar.jpg").path).should eq(0o600)
        end
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
  end
end
