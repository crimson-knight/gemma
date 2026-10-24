require "../grant_helper"

# The shape of `Amber::Router::File`.
private record LifecyclePart, file : File, filename : String?, headers : HTTP::Headers

private def stored_ids : Array(String)
  memory_storage("store").store.keys.sort!
end

private def png_io : IO
  IO::Memory.new(File.read(File.join(SPEC_SUPPORT_DIRECTORY, "300x300.png")).to_slice)
end

private def saved_listing : IntegrationListing
  listing = IntegrationListing.new(title: "first")
  listing.photo = png_io
  listing.floor_plan = IO::Memory.new("plan")
  listing.documents = [IO::Memory.new("one"), IO::Memory.new("two")]
  listing.save || raise "setup: save failed: #{listing.errors.map(&.to_s)}"
  listing
end

describe "Gemma::Grant attachment lifecycle on a real Grant model" do
  before_each { reset_storages }

  it "saves, reloads and reads back the stored file" do
    user = IntegrationUser.new
    user.avatar = IO::Memory.new("avatar bytes")
    user.save.should be_true

    reloaded = IntegrationUser.find!(user.id)
    avatar = reloaded.avatar || fail("expected the reloaded avatar")
    avatar.storage_key.should eq("store")
    avatar.open(&.gets_to_end).should eq("avatar bytes")
    avatar.size.should eq("avatar bytes".bytesize)
  end

  describe "a model with two has_one_attached and one has_many_attached" do
    it "stores all three, each with its own uploader, and reloads them" do
      listing = saved_listing

      reloaded = IntegrationListing.find!(listing.id)
      reloaded.photo.try(&.mime_type).should eq("image/png")
      reloaded.floor_plan.try(&.id).to_s.should start_with("test/")
      reloaded.documents.map(&.open(&.gets_to_end)).should eq(["one", "two"])
      memory_storage("cache").store.should be_empty
      stored_ids.size.should eq(4)
    end

    it "names the list helpers with singular:" do
      listing = saved_listing
      listing.add_document_file(IO::Memory.new("three"))
      listing.save.should be_true

      IntegrationListing.find!(listing.id).documents.size.should eq(3)
    end
  end

  describe "a save that fails after the write" do
    it "deletes the promoted file and keeps the stored one when after_save raises" do
      listing = saved_listing
      old_photo = listing.photo || fail("expected a photo")
      before = stored_ids

      listing.photo = png_io
      listing.fail_after_save = true
      expect_raises(Exception, "after_save failed") { listing.save }

      stored_ids.should eq(before)
      old_photo.exists?.should be_true
      IntegrationListing.find!(listing.id).photo.should eq(old_photo)
    end

    it "promotes again when saved after the failure" do
      listing = saved_listing
      old_photo = listing.photo || fail("expected a photo")
      listing.photo = png_io
      listing.fail_after_save = true
      expect_raises(Exception, "after_save failed") { listing.save }

      listing.fail_after_save = false
      listing.save.should be_true

      new_photo = IntegrationListing.find!(listing.id).photo || fail("expected a photo")
      new_photo.should_not eq(old_photo)
      new_photo.exists?.should be_true
      old_photo.exists?.should be_false
    end

    it "deletes the promoted file when an enclosing transaction rolls back" do
      listing = saved_listing
      old_photo = listing.photo || fail("expected a photo")
      before = stored_ids

      IntegrationListing.transaction do
        listing.photo = png_io
        listing.save.should be_true
        raise Grant::Transaction::Rollback.new
      end

      stored_ids.should eq(before)
      old_photo.exists?.should be_true
    end
  end

  describe "destroy" do
    it "keeps every file when the destroy rolls back" do
      listing = saved_listing
      before = stored_ids

      IntegrationListing.transaction do
        listing.destroy
        raise Grant::Transaction::Rollback.new
      end

      stored_ids.should eq(before)
    end

    it "deletes every stored file once the destroy commits" do
      listing = saved_listing
      listing.destroy.should be_true

      stored_ids.should be_empty
    end
  end

  describe "deferred removal" do
    it "deletes nothing on remove_ or clear_ without a save" do
      listing = saved_listing
      before = stored_ids
      first_document = listing.documents.first

      listing.remove_document_file(first_document)
      listing.documents.size.should eq(1)
      stored_ids.should eq(before)

      listing.clear_documents
      listing.photo = nil
      stored_ids.should eq(before)
    end

    it "deletes the removed files after the save commits" do
      listing = saved_listing
      first_document = listing.documents.first

      listing.remove_document_file(first_document)
      listing.save.should be_true

      first_document.exists?.should be_false
      IntegrationListing.find!(listing.id).documents.size.should eq(1)
    end
  end

  it "takes the client's filename and type claim from an Amber multipart part" do
    part = LifecyclePart.new(tempfile("plan", "upload"), "../floor plan.txt", HTTP::Headers{"Content-Type" => "text/plain"})
    listing = IntegrationListing.new
    listing.floor_plan = part
    listing.save.should be_true

    plan = IntegrationListing.find!(listing.id).floor_plan || fail("expected a floor plan")
    plan.original_filename.should eq("floor plan.txt")
    plan.metadata.extra["declared_content_type"].should eq("text/plain")
  end

  describe "a client's cached-file reference" do
    it "attaches a file the cache holds, with metadata read from its bytes" do
      cached = Gemma.upload(png_io, "cache")
      listing = IntegrationListing.new
      listing.photo = Gemma::CachedFileReference.parse(%({"id":"#{cached.id}","storage_key":"cache","metadata":{"filename":"me.png","size":1,"mime_type":"text/html"}}))
      listing.save.should be_true

      photo = listing.photo || fail("expected a photo")
      photo.mime_type.should eq("image/png")
      photo.size.should eq(cached.size)
      photo.original_filename.should eq("me.png")
    end

    it "refuses a traversal id" do
      listing = IntegrationListing.new

      expect_raises(Gemma::InvalidLocation) do
        listing.photo = Gemma::CachedFileReference.new("../store/x.png", "cache")
      end
    end

    it "refuses a file on another storage" do
      stored = Gemma.upload(png_io, "store")
      listing = IntegrationListing.new

      expect_raises(Gemma::NotCached) do
        listing.photo = Gemma::CachedFileReference.new(stored.id, "store")
      end
    end
  end

  describe "validators" do
    it "rejects a text file when only images are accepted" do
      listing = IntegrationListing.new
      listing.photo = IO::Memory.new("plain text")

      listing.save.should be_false
      listing.errors.map(&.to_s).should eq(["Photo has an invalid content type"])
      stored_ids.should be_empty
    end

    it "fails a size rule when the size is unknown, as in a row without one" do
      profile = IntegrationProfile.new
      profile.avatar_data = Gemma::UploadedFile.new("old.png", "store")

      profile.valid?.should be_false
      profile.errors.map(&.to_s).should eq(["Avatar is too large (maximum is 3 bytes)"])
    end

    it "limits the number of files in a list" do
      listing = IntegrationListing.new
      listing.documents = (1..4).map { |number| IO::Memory.new("doc #{number}") }

      listing.valid?.should be_false
      listing.errors.map(&.to_s).should eq(["Documents has too many files (maximum is 3)"])
    end
  end

  describe "the 0.6 validator names" do
    it "still compile, with a deprecation warning naming the replacement" do
      result = SnippetCompiler.check <<-CRYSTAL
        require "gemma"
        require "sqlite3"
        require "grant"
        require "grant/adapter/sqlite"
        require "gemma/grant"
        Grant::Connections << Grant::Adapter::Sqlite.new(name: "sqlite", url: "sqlite3::memory:")

        class LegacyValidatedUser < Grant::Base
          include Gemma::Grant::Attachable
          include Gemma::Grant::AttachmentValidators

          column id : Int64, primary: true
          has_one_attached :avatar

          validate_file_size_of :avatar, maximum: 5
        end

        LegacyValidatedUser.new.valid?
        CRYSTAL

      result.output.should contain("Deprecated")
      result.output.should contain("validates_attachment_size_of")
      result.exit_code.should eq(0)
    end
  end
end
