require "../../spec_helper"
require "../../../src/gemma/grant"

# Simple mock for Grant::Base to test the macros without database
abstract class MockGrantBase
  macro column(decl, **options)
    {% if decl.is_a?(TypeDeclaration) %}
      property {{decl}}
    {% else %}
      property {{decl.id}}
    {% end %}
  end
  
  macro before_save(method)
    def before_save_hook
      {{method.id}}
    end
  end
  
  macro after_save(method)
    def after_save_hook
      {{method.id}}
    end
  end
  
  macro after_destroy(method)
    def after_destroy_hook
      {{method.id}}
    end
  end
  
  def save
    before_save_hook if responds_to?(:before_save_hook)
    @saved = true
    after_save_hook if responds_to?(:after_save_hook)
    true
  end
  
  def destroy
    after_destroy_hook if responds_to?(:after_destroy_hook)
    @destroyed = true
  end
  
  def saved?
    @saved || false
  end
  
  def destroyed?
    @destroyed || false
  end
end

# Test model with single attachment
class SimpleUser < MockGrantBase
  include Gemma::Grant::Attachable
  
  column name : String?
  column avatar_data : Hash(String, String | Gemma::UploadedFile::MetadataType)?
  
  has_one_attached :avatar
  
  def initialize(@name : String? = nil)
  end
end

# Test model with multiple attachments
class SimplePost < MockGrantBase
  include Gemma::Grant::Attachable
  
  column title : String?
  column images_data : Array(Hash(String, String | Gemma::UploadedFile::MetadataType))?
  
  has_many_attached :images
  
  def initialize(@title : String? = nil)
    @images_data = [] of Hash(String, String | Gemma::UploadedFile::MetadataType)
  end
end

# Custom uploader
class SimpleTestUploader < Gemma
  def generate_location(io : IO | UploadedFile, metadata, **options)
    name = super(io, metadata, **options)
    File.join("test", name)
  end
end

# Test model with custom uploader
class SimpleDocument < MockGrantBase
  include Gemma::Grant::Attachable
  
  column file_data : Hash(String, String | Gemma::UploadedFile::MetadataType)?
  
  has_one_attached :file, uploader: SimpleTestUploader
end

Spectator.describe "Gemma::Grant::Attachable (Simple)" do
  include GemmaHelpers
  include FileHelpers
  
  before_each do
    Gemma.configure do |config|
      config.storages["cache"] = Gemma::Storage::Memory.new
      config.storages["store"] = Gemma::Storage::Memory.new
    end
  end
  
  after_each do
    clear_storages
  end
  
  describe "has_one_attached" do
    let(user) { SimpleUser.new(name: "John") }
    let(io) { fakeio("avatar content", filename: "avatar.jpg") }
    
    it "accepts an IO object" do
      user.avatar = io
      expect(user.avatar).not_to be_nil
      expect(user.avatar_changed?).to be_true
    end
    
    it "accepts nil to remove attachment" do
      user.avatar = io
      user.avatar = nil
      expect(user.avatar).to be_nil
      expect(user.avatar_changed?).to be_true
    end
    
    it "returns nil when no attachment" do
      expect(user.avatar).to be_nil
    end
    
    it "returns the attached file" do
      user.avatar = io
      avatar = user.avatar
      
      expect(avatar).to be_a(Gemma::UploadedFile)
      expect(avatar.not_nil!.metadata["filename"]).to eq("avatar.jpg")
    end
    
    it "returns URL when attachment exists" do
      user.avatar = io
      expect(user.avatar_url).not_to be_nil
      expect(user.avatar_url).to match(/memory:\/\//)
    end
    
    it "promotes cached file on save" do
      user.avatar = io
      avatar_before = user.avatar.not_nil!
      
      expect(avatar_before.storage_key).to eq("cache")
      
      user.save
      
      avatar_after = user.avatar.not_nil!
      expect(avatar_after.storage_key).to eq("store")
    end
    
    it "persists attachment data after save" do
      user.avatar = io
      user.save
      
      expect(user.avatar_data).not_to be_nil
      expect(user.avatar_data.not_nil!["storage_key"]).to eq("store")
      expect(user.avatar_changed?).to be_false
    end
    
    it "destroys attachment on record destroy" do
      user.avatar = io
      user.save
      
      avatar = user.avatar.not_nil!
      expect(avatar.exists?).to be_true
      
      user.destroy
      expect(avatar.exists?).to be_false
    end
  end
  
  describe "has_many_attached" do
    let(post) { SimplePost.new(title: "Test Post") }
    let(io1) { fakeio("image1 content", filename: "image1.jpg") }
    let(io2) { fakeio("image2 content", filename: "image2.jpg") }
    
    it "accepts an array of IO objects" do
      post.images = [io1, io2]
      
      expect(post.images.size).to eq(2)
      expect(post.images_changed?).to be_true
    end
    
    it "returns empty array when no attachments" do
      expect(post.images).to eq([] of Gemma::UploadedFile)
    end
    
    it "returns array of attached files" do
      post.images = [io1, io2]
      images = post.images
      
      expect(images.size).to eq(2)
      expect(images[0]).to be_a(Gemma::UploadedFile)
      expect(images[1]).to be_a(Gemma::UploadedFile)
    end
    
    it "adds a single attachment" do
      post.images = [io1]
      post.add_image(io2)
      
      expect(post.images.size).to eq(2)
      expect(post.images_changed?).to be_true
    end
    
    it "removes specific attachment" do
      post.images = [io1, io2]
      image_to_remove = post.images[0]
      
      post.remove_image(image_to_remove)
      
      expect(post.images.size).to eq(1)
      expect(post.images[0].metadata["filename"]).to eq("image2.jpg")
    end
    
    it "clears all attachments" do
      post.images = [io1, io2]
      post.save
      
      post.clear_images
      
      expect(post.images).to eq([] of Gemma::UploadedFile)
      expect(post.images_changed?).to be_true
    end
    
    it "promotes all cached files on save" do
      post.images = [io1, io2]
      
      post.images.each do |image|
        expect(image.storage_key).to eq("cache")
      end
      
      post.save
      
      post.images.each do |image|
        expect(image.storage_key).to eq("store")
      end
    end
    
    it "persists all attachment data after save" do
      post.images = [io1, io2]
      post.save
      
      expect(post.images_data).not_to be_nil
      expect(post.images_data.not_nil!.size).to eq(2)
      expect(post.images_changed?).to be_false
    end
    
    it "destroys all attachments on record destroy" do
      post.images = [io1, io2]
      post.save
      
      images = post.images.dup
      images.each { |img| expect(img.exists?).to be_true }
      
      post.destroy
      
      images.each { |img| expect(img.exists?).to be_false }
    end
  end
  
  describe "custom uploader" do
    let(document) { SimpleDocument.new }
    let(io) { fakeio("document content", filename: "doc.pdf") }
    
    it "uses the specified custom uploader" do
      document.file = io
      document.save
      
      file = document.file.not_nil!
      # The SimpleTestUploader adds "test/" prefix to the location
      expect(file.id).to match(/^test\//)
    end
  end
  
  describe "edge cases" do
    let(user) { SimpleUser.new }
    
    it "handles multiple saves without changes" do
      user.avatar = fakeio("content")
      user.save
      
      avatar_id = user.avatar.not_nil!.id
      user.save # Second save without changes
      
      expect(user.avatar.not_nil!.id).to eq(avatar_id)
      expect(user.avatar_changed?).to be_false
    end
    
    it "handles attachment replacement" do
      user.avatar = fakeio("old content")
      user.save
      
      old_avatar = user.avatar.not_nil!
      
      user.avatar = fakeio("new content")
      expect(user.avatar_changed?).to be_true
      
      user.save
      
      expect(user.avatar.not_nil!.id).not_to eq(old_avatar.id)
      expect(old_avatar.exists?).to be_false
    end
    
    it "handles nil avatar_data on initialization" do
      user = SimpleUser.new
      expect(user.avatar).to be_nil
      expect(user.avatar_url).to be_nil
    end
  end
end