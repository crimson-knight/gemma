require "gemma"
require "gemma/grant"
require "grant"

# Configure Gemma
Gemma.configure do |config|
  config.storages["cache"] = Gemma::Storage::FileSystem.new("uploads", prefix: "cache")
  config.storages["store"] = Gemma::Storage::FileSystem.new("uploads")
end

# Custom uploader with built-in validations
class AvatarUploader < Gemma
  # Maximum 5MB
  MAX_SIZE = 5.megabytes
  
  # Only allow images
  ALLOWED_TYPES = %w[image/jpeg image/png image/gif image/webp]
  
  def extract_metadata(io, **options)
    metadata = super
    
    # Validate file size
    if size = metadata["size"]?.try(&.to_i)
      if size > MAX_SIZE
        raise Gemma::InvalidFile.new(io, "Avatar too large (max 5MB)")
      end
    end
    
    # Validate MIME type
    if mime_type = metadata["mime_type"]?.try(&.to_s)
      unless ALLOWED_TYPES.includes?(mime_type)
        raise Gemma::InvalidFile.new(io, "Avatar must be an image (JPEG, PNG, GIF, or WebP)")
      end
    end
    
    metadata
  end
end

# User model with validated attachments
class User < Grant::Base
  include Gemma::Grant::Attachable
  include Gemma::Grant::AttachmentValidators
  
  self.connection_name = "primary"
  self.table_name = "users"
  
  # Columns
  column id : Int64, primary: true
  column email : String
  column name : String?
  column avatar_data : JSON::Any?
  column documents_data : JSON::Any?
  column created_at : Time?
  column updated_at : Time?
  
  # Attachments
  has_one_attached :avatar, uploader: AvatarUploader
  has_many_attached :documents
  
  # Standard validations
  validates :email, presence: true, uniqueness: true
  validates :name, presence: true, length: {minimum: 2, maximum: 100}
  
  # Attachment validations
  validate_presence_of :avatar, message: "Please upload an avatar"
  
  validate_file_size_of :avatar, 
    maximum: 5.megabytes,
    message: "Avatar file is too large (max 5MB)"
  
  validate_content_type_of :avatar,
    accept: ["image/jpeg", "image/png", "image/gif", "image/webp"],
    message: "Avatar must be an image file"
  
  # For images with dimensions (requires StoreDimensions plugin)
  validate_dimensions_of :avatar,
    width: 100..2000,
    height: 100..2000,
    message: "Avatar dimensions must be between 100x100 and 2000x2000 pixels"
  
  # Validate collection of documents
  validate_collection_size_of :documents,
    maximum: 10,
    message: "You can upload a maximum of 10 documents"
  
  # Custom validation
  validate :validate_total_storage_usage
  
  private def validate_total_storage_usage
    total_size = 0
    
    # Add avatar size
    if avatar = self.avatar
      total_size += avatar.size || 0
    end
    
    # Add all document sizes
    documents.each do |doc|
      total_size += doc.size || 0
    end
    
    # 50MB total limit per user
    if total_size > 50.megabytes
      errors.add(:base, "Total file storage exceeds 50MB limit")
    end
  end
end

# Profile model with different validation rules
class Profile < Grant::Base
  include Gemma::Grant::Attachable
  include Gemma::Grant::AttachmentValidators
  
  self.connection_name = "primary"
  self.table_name = "profiles"
  
  column id : Int64, primary: true
  column user_id : Int64
  column bio : String?
  column resume_data : JSON::Any?
  column portfolio_data : JSON::Any?
  
  has_one_attached :resume
  has_many_attached :portfolio
  
  # Resume must be PDF or Word doc
  validate_content_type_of :resume,
    accept: [
      "application/pdf",
      "application/msword",
      "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
    ],
    message: "Resume must be a PDF or Word document"
  
  # Resume max 10MB
  validate_file_size_of :resume,
    maximum: 10.megabytes
  
  # Portfolio items must be images or PDFs
  validate :validate_portfolio_items
  
  private def validate_portfolio_items
    portfolio.each_with_index do |item, index|
      mime_type = item.mime_type
      
      unless mime_type && (mime_type.starts_with?("image/") || mime_type == "application/pdf")
        errors.add(:portfolio, "Item #{index + 1} must be an image or PDF")
      end
      
      # Each portfolio item max 20MB
      if size = item.size
        if size > 20.megabytes
          errors.add(:portfolio, "Item #{index + 1} is too large (max 20MB)")
        end
      end
    end
  end
end

# Usage example
def create_user_with_validation
  user = User.new(
    email: "user@example.com",
    name: "John Doe"
  )
  
  # Try to save without avatar (will fail validation)
  unless user.save
    puts "Validation errors:"
    user.errors.full_messages.each do |message|
      puts "  - #{message}"
    end
  end
  
  # Add avatar
  File.open("avatar.jpg") do |file|
    user.avatar = file
  end
  
  # Add documents
  user.documents = [
    File.open("doc1.pdf"),
    File.open("doc2.pdf")
  ]
  
  if user.save
    puts "User saved successfully!"
    puts "Avatar URL: #{user.avatar_url}"
    puts "Documents: #{user.documents.size}"
  else
    puts "Validation errors:"
    user.errors.full_messages.each do |message|
      puts "  - #{message}"
    end
  end
rescue ex : Gemma::InvalidFile
  puts "File validation error: #{ex.message}"
end

# Controller example with error handling
class UsersController < ApplicationController
  def create
    user = User.new(user_params)
    
    # Handle file uploads with validation
    if avatar = params.files["avatar"]?
      begin
        user.avatar = avatar.file
      rescue ex : Gemma::InvalidFile
        user.errors.add(:avatar, ex.message)
      end
    end
    
    if documents = params.files.select("documents[]")
      begin
        user.documents = documents.map(&.file)
      rescue ex : Gemma::InvalidFile
        user.errors.add(:documents, ex.message)
      end
    end
    
    if user.save
      flash["success"] = "User created successfully!"
      redirect_to "/users/#{user.id}"
    else
      flash["error"] = user.errors.full_messages.join(", ")
      render "new.slang", locals: {user: user}
    end
  end
  
  private def user_params
    params.validation do
      required :email
      required :name
    end
  end
end