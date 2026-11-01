require "../grant_helper"

# followup-10-evidence/persist_probe.cr: with real Grant and SQLite, a saved
# attachment never reached the database, and the cached copy stayed behind.
describe "persist probe" do
  before_each { reset_storages }

  it "writes has_one_attached's column in the same save" do
    user = IntegrationUser.new
    user.avatar = IO::Memory.new("hello")
    user.save || raise "setup: save failed"

    reloaded = IntegrationUser.find!(user.id)
    reloaded.avatar_data.should_not be_nil
    reloaded.avatar.try(&.storage_key).should eq("store")
  end

  it "writes has_many_attached's column in the same save" do
    post = IntegrationPost.new
    post.images = [IO::Memory.new("one"), IO::Memory.new("two")]
    post.save || raise "setup: save failed"

    IntegrationPost.find!(post.id).images.size.should eq(2)
  end

  it "deletes the cached copy once the file is promoted" do
    user = IntegrationUser.new
    user.avatar = IO::Memory.new("hello")
    user.save || raise "setup: save failed"

    memory_storage("cache").store.size.should eq(0)
  end

  it "stores nothing permanently when validation fails" do
    profile = IntegrationProfile.new
    profile.avatar = IO::Memory.new("too big")

    profile.save.should be_false
    profile.errors.map(&.to_s).should eq(["Avatar is too large (maximum is 3 bytes)"])
    memory_storage("store").store.size.should eq(0)
  end

  it "rejects a text file when only images are accepted" do
    profile = IntegrationProfile.new
    profile.cover = IO::Memory.new("plain text, not an image")

    profile.save.should be_false
  end

  it "rejects a file of unknown type when only images are accepted" do
    profile = IntegrationProfile.new
    profile.cover = IO::Memory.new("\u0000\u0001 bytes no analyzer recognizes")

    profile.save.should be_false
  end
end
