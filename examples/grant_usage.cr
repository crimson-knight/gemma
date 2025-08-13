require "gemma"
require "gemma/grant"

# Configure Gemma storages
Gemma.configure do |config|
  config.storages["cache"] = Gemma::Storage::FileSystem.new("uploads", prefix: "cache")
  config.storages["store"] = Gemma::Storage::FileSystem.new("uploads")
end

# Define custom uploaders
class AvatarUploader < Gemma
  def generate_location(io : IO | UploadedFile, metadata, **options)
    name = super(io, metadata, **options)
    File.join("avatars", Time.utc.to_s("%Y/%m"), name)
  end
  
  finalize_plugins!
end

class DocumentUploader < Gemma
  def generate_location(io : IO | UploadedFile, metadata, **options)
    name = super(io, metadata, **options)
    File.join("documents", Time.utc.to_s("%Y/%m"), name)
  end
  
  finalize_plugins!
end

# Example Grant model with attachments
class User < Grant::Model
  include Gemma::Grant::Attachable
  
  connection pg
  table users
  
  column id : Int64, primary: true
  column name : String
  column email : String
  column avatar_data : JSON::Any?
  column documents_data : JSON::Any?
  
  # Single file attachment
  has_one_attached :avatar, uploader: AvatarUploader
  
  # Multiple file attachments
  has_many_attached :documents, uploader: DocumentUploader
end

# Usage examples
def example_usage
  user = User.new(name: "John Doe", email: "john@example.com")
  
  # Attach single file from form upload
  # user.avatar = params.files["avatar"]
  
  # Attach single file from IO
  File.open("path/to/avatar.jpg") do |file|
    user.avatar = file
  end
  
  # Attach multiple files
  # user.documents = params.files.select("documents[]")
  
  # Add individual document
  File.open("path/to/document.pdf") do |file|
    user.add_document(file)
  end
  
  # Save user (this will promote cached files to permanent storage)
  user.save
  
  # Access attachments
  if avatar = user.avatar
    puts "Avatar URL: #{avatar.url}"
    puts "Avatar size: #{avatar.size}"
    puts "Avatar MIME type: #{avatar.mime_type}"
  end
  
  # Access multiple attachments
  user.documents.each do |document|
    puts "Document: #{document.original_filename}"
    puts "URL: #{document.url}"
  end
  
  # Remove specific document
  if doc = user.documents.first?
    user.remove_document(doc)
  end
  
  # Clear all documents
  user.clear_documents
  
  # Update avatar with a new file
  File.open("path/to/new_avatar.jpg") do |file|
    user.avatar = file
  end
  user.save # Old avatar will be deleted, new one promoted
  
  # Remove avatar
  user.avatar = nil
  user.save
end

# Example with Amber framework
class UsersController < ApplicationController
  def create
    user = User.new(user_params)
    
    # Handle avatar upload
    if avatar = params.files["avatar"]?
      user.avatar = avatar
    end
    
    # Handle multiple document uploads
    if documents = params.files.select("documents[]")
      user.documents = documents
    end
    
    if user.save
      redirect_to "/users/#{user.id}", flash: {"success" => "User created successfully"}
    else
      render "new.slang"
    end
  end
  
  def update
    user = User.find!(params["id"])
    user.set_attributes(user_params)
    
    # Handle avatar update
    if params.has_key?("remove_avatar")
      user.avatar = nil
    elsif avatar = params.files["avatar"]?
      user.avatar = avatar
    end
    
    # Add new documents without removing existing ones
    if documents = params.files.select("documents[]")
      documents.each do |doc|
        user.add_document(doc)
      end
    end
    
    if user.save
      redirect_to "/users/#{user.id}", flash: {"success" => "User updated successfully"}
    else
      render "edit.slang"
    end
  end
  
  private def user_params
    params.validation do
      required :name
      required :email
    end
  end
end