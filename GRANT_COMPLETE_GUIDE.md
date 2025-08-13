# Complete Grant ORM Integration Guide for Gemma

This comprehensive guide covers all aspects of integrating Gemma file attachments with Grant ORM models.

## Table of Contents
1. [Installation & Setup](#installation--setup)
2. [Basic Usage](#basic-usage)
3. [Advanced Features](#advanced-features)
4. [Database Migrations](#database-migrations)
5. [Web Framework Integration](#web-framework-integration)
6. [Testing](#testing)
7. [Best Practices](#best-practices)
8. [Troubleshooting](#troubleshooting)

## Installation & Setup

### 1. Add Dependencies

Update your `shard.yml`:

```yaml
dependencies:
  gemma:
    github: crimson-knight/gemma
  grant:
    github: crimson-knight/grant
    branch: main
  
  # Database drivers (choose what you need)
  pg:
    github: will/crystal-pg
  mysql:
    github: crystal-lang/crystal-mysql
  sqlite3:
    github: crystal-lang/crystal-sqlite3
```

### 2. Configure Gemma Storage

```crystal
require "gemma"
require "gemma/grant"

# Configure storage backends
Gemma.configure do |config|
  # Temporary storage for uploads
  config.storages["cache"] = Gemma::Storage::FileSystem.new(
    "uploads/cache",
    prefix: "cache"
  )
  
  # Permanent storage
  config.storages["store"] = Gemma::Storage::FileSystem.new(
    "uploads/store"
  )
end

# For S3 storage
require "awscr-s3"

client = Awscr::S3::Client.new(
  region: ENV["AWS_REGION"],
  aws_access_key: ENV["AWS_ACCESS_KEY_ID"],
  aws_secret_key: ENV["AWS_SECRET_ACCESS_KEY"]
)

Gemma.configure do |config|
  config.storages["store"] = Gemma::Storage::S3.new(
    bucket: ENV["S3_BUCKET"],
    client: client,
    public: true
  )
end
```

### 3. Configure Grant Database

```crystal
require "grant"

# PostgreSQL
Grant::Connections << Grant::Adapter::Pg.new(
  name: "primary",
  url: ENV["DATABASE_URL"]
)

# MySQL
Grant::Connections << Grant::Adapter::Mysql.new(
  name: "primary", 
  url: ENV["DATABASE_URL"]
)

# SQLite
Grant::Connections << Grant::Adapter::Sqlite.new(
  name: "primary",
  url: "sqlite3:./db/development.db"
)
```

## Basic Usage

### Single File Attachments

```crystal
class User < Grant::Base
  include Gemma::Grant::Attachable
  
  # Database configuration
  self.connection_name = "primary"
  self.table_name = "users"
  
  # Columns
  column id : Int64, primary: true
  column email : String
  column name : String?
  column avatar_data : JSON::Any?
  column created_at : Time?
  column updated_at : Time?
  
  # Define single attachment
  has_one_attached :avatar
end

# Usage
user = User.new(email: "user@example.com", name: "John Doe")

# Attach a file
File.open("avatar.jpg") do |file|
  user.avatar = file
end

# Save (promotes from cache to permanent storage)
user.save

# Access attachment
if avatar = user.avatar
  puts "URL: #{avatar.url}"
  puts "Size: #{avatar.size} bytes"
  puts "MIME: #{avatar.mime_type}"
  puts "Filename: #{avatar.original_filename}"
end

# Generate URLs with options
user.avatar_url                    # Basic URL
user.avatar_url(expires_in: 3600)  # S3 presigned URL

# Remove attachment
user.avatar = nil
user.save
```

### Multiple File Attachments

```crystal
class Product < Grant::Base
  include Gemma::Grant::Attachable
  
  self.connection_name = "primary"
  self.table_name = "products"
  
  column id : Int64, primary: true
  column name : String
  column description : String?
  column images_data : JSON::Any?
  column created_at : Time?
  column updated_at : Time?
  
  # Define multiple attachments
  has_many_attached :images
end

# Usage
product = Product.new(name: "Cool Product")

# Attach multiple files
product.images = [
  File.open("image1.jpg"),
  File.open("image2.jpg"),
  File.open("image3.jpg")
]
product.save

# Access attachments
product.images.each_with_index do |image, index|
  puts "Image #{index + 1}: #{image.url}"
end

# Add single image
File.open("image4.jpg") do |file|
  product.add_image(file)
end
product.save

# Remove specific image
if image = product.images.first?
  product.remove_image(image)
  product.save
end

# Clear all images
product.clear_images
product.save
```

## Advanced Features

### Custom Uploaders

Create specialized uploaders for different file types:

```crystal
# Base image uploader with processing
class ImageUploader < Gemma
  # Load plugins for image processing
  load_plugin(Gemma::Plugins::DetermineMimeType)
  load_plugin(Gemma::Plugins::StoreDimensions)
  
  def generate_location(io : IO | UploadedFile, metadata, **options)
    name = super(io, metadata, **options)
    # Organize by year/month
    File.join("images", Time.utc.to_s("%Y/%m"), name)
  end
  
  # Validate file type
  def extract_metadata(io, **options)
    metadata = super
    mime_type = metadata["mime_type"]?
    
    unless mime_type && mime_type.to_s.starts_with?("image/")
      raise Gemma::InvalidFile.new(io, "Must be an image file")
    end
    
    metadata
  end
end

# Document uploader with virus scanning
class DocumentUploader < Gemma
  def generate_location(io : IO | UploadedFile, metadata, **options)
    name = super(io, metadata, **options)
    File.join("documents", Time.utc.to_s("%Y/%m"), name)
  end
  
  def upload(io : IO | UploadedFile, **options)
    # Add virus scanning here
    # scan_for_viruses!(io)
    super
  end
end

# Use custom uploaders
class Article < Grant::Base
  include Gemma::Grant::Attachable
  
  column id : Int64, primary: true
  column title : String
  column featured_image_data : JSON::Any?
  column attachments_data : JSON::Any?
  
  has_one_attached :featured_image, uploader: ImageUploader
  has_many_attached :attachments, uploader: DocumentUploader
end
```

### Direct Uploads

For large files, upload directly to storage from the browser:

```crystal
# Generate presigned upload URL (S3)
class DirectUploadController < ApplicationController
  def create
    # Generate unique key
    key = "uploads/#{SecureRandom.hex}/#{params["filename"]}"
    
    # Get S3 storage
    storage = Gemma.find_storage("store").as(Gemma::Storage::S3)
    
    # Generate presigned POST data
    presigned = storage.client.presigned_post(
      bucket: storage.bucket,
      key: key,
      expires_in: 1.hour.total_seconds.to_i,
      conditions: [
        {"content-type" => params["content_type"]},
        ["content-length-range", 0, 100.megabytes]
      ]
    )
    
    respond_with do
      json({
        url: presigned.url,
        fields: presigned.fields,
        key: key
      })
    end
  end
end

# After direct upload, attach the uploaded file
user.avatar = {
  "id" => key,
  "storage_key" => "store",
  "metadata" => {
    "filename" => params["filename"],
    "size" => params["size"],
    "mime_type" => params["content_type"]
  }
}
user.save
```

## Database Migrations

### PostgreSQL / MySQL

```crystal
class CreateUsersWithAttachments < Grant::Migration
  def up
    create_table :users do |t|
      t.string :email, null: false
      t.string :name
      t.json :avatar_data      # For single attachment
      t.json :documents_data   # For multiple attachments
      t.timestamps
    end
    
    add_index :users, :email, unique: true
  end
  
  def down
    drop_table :users
  end
end
```

### SQLite

```crystal
class CreateUsersWithAttachments < Grant::Migration
  def up
    create_table :users do |t|
      t.string :email, null: false
      t.string :name
      t.text :avatar_data      # SQLite uses TEXT for JSON
      t.text :documents_data
      t.timestamps
    end
  end
  
  def down
    drop_table :users
  end
end
```

## Web Framework Integration

### Amber Framework

```crystal
class UsersController < ApplicationController
  def new
    user = User.new
    render "new.slang", locals: {user: user}
  end
  
  def create
    user = User.new(user_params)
    
    # Handle avatar upload
    if avatar_upload = params.files["user[avatar]"]?
      user.avatar = avatar_upload.file
    end
    
    # Handle multiple document uploads
    if document_uploads = params.files.select("user[documents][]")
      user.documents = document_uploads.map(&.file)
    end
    
    if user.save
      redirect_to "/users/#{user.id}", flash: {"success" => "User created!"}
    else
      render "new.slang", locals: {user: user}, status: 422
    end
  end
  
  def update
    user = User.find!(params["id"])
    user.assign_attributes(user_params)
    
    # Handle avatar replacement
    if params["remove_avatar"]?
      user.avatar = nil
    elsif avatar_upload = params.files["user[avatar]"]?
      user.avatar = avatar_upload.file
    end
    
    # Add new documents without removing existing
    if document_uploads = params.files.select("user[documents][]")
      document_uploads.each do |upload|
        user.add_document(upload.file)
      end
    end
    
    # Handle document removals
    if remove_ids = params["remove_documents"]?
      remove_ids = Array(String).from_json(remove_ids)
      user.documents.each do |doc|
        if remove_ids.includes?(doc.id)
          user.remove_document(doc)
        end
      end
    end
    
    if user.save
      redirect_to "/users/#{user.id}", flash: {"success" => "Updated!"}
    else
      render "edit.slang", locals: {user: user}, status: 422
    end
  end
  
  private def user_params
    params.validation do
      required :email
      optional :name
    end
  end
end
```

### View Templates (Slang)

```slang
/ new.slang
form action="/users" method="post" enctype="multipart/form-data"
  .field
    label for="user_email" Email
    input type="email" name="user[email]" id="user_email" required=true
  
  .field
    label for="user_name" Name
    input type="text" name="user[name]" id="user_name"
  
  .field
    label for="user_avatar" Avatar
    input type="file" name="user[avatar]" id="user_avatar" accept="image/*"
  
  .field
    label for="user_documents" Documents
    input type="file" name="user[documents][]" id="user_documents" multiple=true
  
  button type="submit" Create User

/ edit.slang
form action="/users/#{user.id}" method="post" enctype="multipart/form-data"
  input type="hidden" name="_method" value="PATCH"
  
  - if avatar = user.avatar
    .current-avatar
      img src=user.avatar_url width="150"
      label
        input type="checkbox" name="remove_avatar" value="1"
        | Remove avatar
  
  .field
    label for="user_avatar" 
      - if user.avatar
        | Replace Avatar
      - else
        | Add Avatar
    input type="file" name="user[avatar]" id="user_avatar" accept="image/*"
  
  - if user.documents.any?
    .current-documents
      h3 Current Documents
      ul
        - user.documents.each do |doc|
          li
            a href=doc.url = doc.original_filename || doc.id
            label
              input type="checkbox" name="remove_documents[]" value=doc.id
              | Remove
  
  .field
    label for="user_documents" Add Documents
    input type="file" name="user[documents][]" id="user_documents" multiple=true
  
  button type="submit" Update User
```

## Testing

### Unit Tests

```crystal
require "spec"
require "../src/models/user"

describe User do
  before_each do
    # Setup test storages
    Gemma.configure do |config|
      config.storages["cache"] = Gemma::Storage::Memory.new
      config.storages["store"] = Gemma::Storage::Memory.new
    end
  end
  
  describe "avatar attachment" do
    it "attaches and saves avatar" do
      user = User.new(email: "test@example.com")
      
      File.open("spec/fixtures/avatar.jpg") do |file|
        user.avatar = file
        user.avatar_changed?.should be_true
      end
      
      user.save.should be_true
      user.avatar_changed?.should be_false
      
      avatar = user.avatar.not_nil!
      avatar.storage_key.should eq("store")
      avatar.exists?.should be_true
    end
    
    it "removes avatar" do
      user = User.create!(email: "test@example.com")
      
      File.open("spec/fixtures/avatar.jpg") do |file|
        user.avatar = file
        user.save
      end
      
      avatar = user.avatar.not_nil!
      
      user.avatar = nil
      user.save
      
      user.avatar.should be_nil
      avatar.exists?.should be_false
    end
    
    it "replaces avatar and cleans up old file" do
      user = User.create!(email: "test@example.com")
      
      # First avatar
      File.open("spec/fixtures/avatar1.jpg") do |file|
        user.avatar = file
        user.save
      end
      
      old_avatar = user.avatar.not_nil!
      
      # Replace with new avatar
      File.open("spec/fixtures/avatar2.jpg") do |file|
        user.avatar = file
        user.save
      end
      
      new_avatar = user.avatar.not_nil!
      
      old_avatar.id.should_not eq(new_avatar.id)
      old_avatar.exists?.should be_false
      new_avatar.exists?.should be_true
    end
  end
  
  describe "documents attachment" do
    it "attaches multiple documents" do
      user = User.new(email: "test@example.com")
      
      files = ["doc1.pdf", "doc2.pdf"].map do |name|
        File.open("spec/fixtures/#{name}")
      end
      
      user.documents = files
      user.save
      
      user.documents.size.should eq(2)
      user.documents.all?(&.exists?).should be_true
    ensure
      files.try &.each(&.close)
    end
    
    it "adds document to existing collection" do
      user = User.create!(email: "test@example.com")
      
      File.open("spec/fixtures/doc1.pdf") do |file|
        user.documents = [file]
        user.save
      end
      
      user.documents.size.should eq(1)
      
      File.open("spec/fixtures/doc2.pdf") do |file|
        user.add_document(file)
        user.save
      end
      
      user.documents.size.should eq(2)
    end
  end
end
```

### Integration Tests

```crystal
describe "File Upload Integration" do
  it "handles form upload" do
    post "/users", body: "user[email]=test@example.com", headers: HTTP::Headers{
      "Content-Type" => "multipart/form-data"
    }, files: {
      "user[avatar]" => File.open("spec/fixtures/avatar.jpg")
    }
    
    response.status_code.should eq(302)
    
    user = User.find_by!(email: "test@example.com")
    user.avatar.should_not be_nil
  end
end
```

## Best Practices

### 1. Security

```crystal
class SecureUploader < Gemma
  # Whitelist allowed MIME types
  ALLOWED_TYPES = %w[
    image/jpeg image/png image/gif
    application/pdf
    application/msword
    application/vnd.openxmlformats-officedocument.wordprocessingml.document
  ]
  
  # Maximum file size (10MB)
  MAX_SIZE = 10.megabytes
  
  def extract_metadata(io, **options)
    metadata = super
    
    # Check MIME type
    mime_type = metadata["mime_type"]?.try(&.to_s)
    unless mime_type && ALLOWED_TYPES.includes?(mime_type)
      raise Gemma::InvalidFile.new(io, "File type not allowed")
    end
    
    # Check file size
    size = metadata["size"]?.try(&.to_i)
    if size && size > MAX_SIZE
      raise Gemma::InvalidFile.new(io, "File too large (max #{MAX_SIZE} bytes)")
    end
    
    metadata
  end
  
  # Sanitize filename
  def generate_location(io : IO | UploadedFile, metadata, **options)
    original = metadata["filename"]?.try(&.to_s) || "file"
    
    # Remove unsafe characters
    safe_name = original.gsub(/[^a-zA-Z0-9\.\-_]/, "_")
    
    # Ensure unique name
    "#{Time.utc.to_unix}_#{Random.rand(1000)}_#{safe_name}"
  end
end
```

### 2. Performance

```crystal
# Use background jobs for processing
class ImageProcessor
  include Sidekiq::Worker
  
  def perform(user_id : Int64)
    user = User.find!(user_id)
    
    if avatar = user.avatar
      # Generate thumbnails
      avatar.download do |tempfile|
        # Process with ImageMagick
        system("convert #{tempfile.path} -thumbnail 200x200 #{tempfile.path}.thumb.jpg")
        
        # Upload thumbnail
        File.open("#{tempfile.path}.thumb.jpg") do |thumb|
          user.avatar_thumbnail = thumb
          user.save
        end
      end
    end
  end
end

# Enqueue after upload
after_save :process_avatar_async

private def process_avatar_async
  if avatar_changed? && avatar
    ImageProcessor.async.perform(id.not_nil!)
  end
end
```

### 3. Cleanup

```crystal
# Periodic cleanup of orphaned cache files
class CacheCleanupJob
  def self.perform
    cache = Gemma.find_storage("cache")
    cutoff = 24.hours.ago
    
    # Remove old cached files
    cache.clear_cache(older_than: cutoff)
  end
end
```

## Troubleshooting

### Common Issues

**1. Files not persisting after save**
- Ensure callbacks are properly defined
- Check that the column exists in database
- Verify storage configuration

**2. Memory issues with large files**
- Use streaming for large files
- Implement direct uploads
- Process files in background jobs

**3. Permission errors**
- Check directory permissions for file storage
- Ensure S3 bucket policies are correct
- Verify IAM credentials have necessary permissions

**4. JSON parsing errors**
- Ensure column type supports JSON (JSON for PostgreSQL/MySQL, TEXT for SQLite)
- Check for proper serialization

### Debugging

```crystal
# Enable Gemma logging
Log.setup_from_env(default_level: :debug)

# Inspect attachment state
puts user.avatar_changed?
puts user.avatar_data
puts user.avatar.try(&.storage_key)

# Check storage directly
storage = Gemma.find_storage("store")
puts storage.exists?(user.avatar.try(&.id))
```

## Migration from ActiveStorage

If migrating from Rails ActiveStorage:

```crystal
class MigrateFromActiveStorage < Grant::Migration
  def up
    User.find_each do |user|
      if blob_id = user.avatar_blob_id
        blob = ActiveStorageBlob.find(blob_id)
        
        # Download from ActiveStorage
        temp_file = download_blob(blob)
        
        # Upload to Gemma
        user.avatar = temp_file
        user.save
        
        temp_file.delete
      end
    end
  end
end
```

## Support

For issues and questions:
- GitHub Issues: https://github.com/crimson-knight/gemma/issues
- Documentation: https://github.com/crimson-knight/gemma/wiki
- Examples: https://github.com/crimson-knight/gemma/tree/main/examples