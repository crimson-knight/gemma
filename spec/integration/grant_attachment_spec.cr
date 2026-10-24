require "../grant_helper"

private def avatar_io : FakeIO
  fakeio("avatar content", filename: "avatar.jpg")
end

private def image_io(number : Int32) : FakeIO
  fakeio("image#{number} content", filename: "image#{number}.jpg")
end

private def saved_file(record_file : Gemma::UploadedFile?) : Gemma::UploadedFile
  record_file || fail("expected an attached file")
end

describe "Gemma::Grant::Attachable on a real Grant model" do
  before_each { reset_storages }

  describe "has_one_attached" do
    it "accepts an IO object" do
      user = IntegrationUser.new(first_name: "John")
      user.avatar = avatar_io

      user.avatar.should_not be_nil
      user.avatar_changed?.should be_true
    end

    it "accepts nil to remove the attachment" do
      user = IntegrationUser.new
      user.avatar = avatar_io
      user.avatar = nil

      user.avatar.should be_nil
      user.avatar_changed?.should be_true
    end

    it "returns nil when nothing is attached" do
      IntegrationUser.new.avatar.should be_nil
    end

    it "returns the attached file with its metadata" do
      user = IntegrationUser.new
      user.avatar = avatar_io

      avatar = saved_file(user.avatar)
      avatar.should be_a(Gemma::UploadedFile)
      avatar.metadata["filename"].should eq("avatar.jpg")
    end

    it "returns a URL when a file is attached" do
      user = IntegrationUser.new
      user.avatar = avatar_io

      user.avatar_url.to_s.should start_with("memory://")
    end

    it "promotes the cached file on save" do
      user = IntegrationUser.new
      user.avatar = avatar_io
      saved_file(user.avatar).storage_key.should eq("cache")

      user.save.should be_true

      saved_file(user.avatar).storage_key.should eq("store")
    end

    it "sets the column in memory and clears the changed flag after save" do
      user = IntegrationUser.new
      user.avatar = avatar_io
      user.save

      user.avatar_data.try(&.["storage_key"]?).should eq("store")
      user.avatar_changed?.should be_false
    end

    it "deletes the stored file when the record is destroyed" do
      user = IntegrationUser.new
      user.avatar = avatar_io
      user.save
      avatar = saved_file(user.avatar)
      avatar.exists?.should be_true

      user.destroy

      avatar.exists?.should be_false
    end
  end

  describe "has_many_attached" do
    it "accepts an array of IO objects" do
      post = IntegrationPost.new(title: "Test Post")
      post.images = [image_io(1), image_io(2)]

      post.images.size.should eq(2)
      post.images_changed?.should be_true
    end

    it "returns an empty array when nothing is attached" do
      IntegrationPost.new.images.should eq([] of Gemma::UploadedFile)
    end

    it "returns the attached files" do
      post = IntegrationPost.new
      post.images = [image_io(1), image_io(2)]

      post.images.size.should eq(2)
      post.images.each(&.should(be_a(Gemma::UploadedFile)))
    end

    it "adds a single attachment" do
      post = IntegrationPost.new
      post.images = [image_io(1)]
      post.add_image(image_io(2))

      post.images.size.should eq(2)
      post.images_changed?.should be_true
    end

    it "removes one attachment" do
      post = IntegrationPost.new
      post.images = [image_io(1), image_io(2)]

      post.remove_image(post.images[0])

      post.images.size.should eq(1)
      post.images[0].metadata["filename"].should eq("image2.jpg")
    end

    it "clears all attachments" do
      post = IntegrationPost.new
      post.images = [image_io(1), image_io(2)]
      post.save

      post.clear_images

      post.images.should eq([] of Gemma::UploadedFile)
      post.images_changed?.should be_true
    end

    it "promotes every cached file on save" do
      post = IntegrationPost.new
      post.images = [image_io(1), image_io(2)]
      post.images.map(&.storage_key).should eq(["cache", "cache"])

      post.save

      post.images.map(&.storage_key).should eq(["store", "store"])
    end

    it "sets the column in memory and clears the changed flag after save" do
      post = IntegrationPost.new
      post.images = [image_io(1), image_io(2)]
      post.save

      post.images_data.try(&.size).should eq(2)
      post.images_changed?.should be_false
    end

    it "deletes every stored file when the record is destroyed" do
      post = IntegrationPost.new
      post.images = [image_io(1), image_io(2)]
      post.save
      images = post.images.dup
      images.all?(&.exists?).should be_true

      post.destroy

      images.none?(&.exists?).should be_true
    end
  end

  describe "a custom uploader" do
    it "stores the file where the uploader says" do
      document = IntegrationDocument.new
      document.file = fakeio("document content", filename: "doc.pdf")
      document.save

      saved_file(document.file).id.should start_with("test/")
    end
  end

  describe "edge cases" do
    it "keeps the file across saves without changes" do
      user = IntegrationUser.new
      user.avatar = fakeio("content")
      user.save
      avatar_id = saved_file(user.avatar).id

      user.save

      saved_file(user.avatar).id.should eq(avatar_id)
      user.avatar_changed?.should be_false
    end

    it "deletes the replaced file" do
      user = IntegrationUser.new
      user.avatar = fakeio("old content")
      user.save
      old_avatar = saved_file(user.avatar)

      user.avatar = fakeio("new content")
      user.avatar_changed?.should be_true
      user.save

      saved_file(user.avatar).id.should_not eq(old_avatar.id)
      old_avatar.exists?.should be_false
    end

    it "has no file or URL for a new record" do
      user = IntegrationUser.new
      user.avatar.should be_nil
      user.avatar_url.should be_nil
    end
  end
end
