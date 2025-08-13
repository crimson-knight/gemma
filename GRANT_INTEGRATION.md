# Gemma Grant ORM Integration

This document describes how to use Gemma with Grant ORM to add file attachment capabilities to your models.

## Installation

Make sure you have both Gemma and Grant in your `shard.yml`:

```yaml
dependencies:
  gemma:
    github: crimson-knight/gemma
  grant:
    github: crimson-knight/grant
```

## Setup

First, configure Gemma's storage backends:

```crystal
require "gemma"
require "gemma/grant"

Gemma.configure do |config|
  config.storages["cache"] = Gemma::Storage::FileSystem.new("uploads", prefix: "cache")
  config.storages["store"] = Gemma::Storage::FileSystem.new("uploads")
end
```

## Adding Attachments to Models

Include the `Gemma::Grant::Attachable` module in your Grant models:

```crystal
class User < Grant::Model
  include Gemma::Grant::Attachable
  
  connection pg
  table users
  
  column id : Int64, primary: true
  column name : String
  column avatar_data : JSON::Any?
  
  # Define a single file attachment
  has_one_attached :avatar
end
```

## Database Migrations

Add JSON columns to store attachment metadata:

```crystal
class AddAvatarToUsers < Grant::Migration
  def up
    alter_table :users do
      add_column :avatar_data, :json
    end
  end
  
  def down
    alter_table :users do
      drop_column :avatar_data
    end
  end
end
```

## Single File Attachments

Use `has_one_attached` for single file attachments:

```crystal
class User < Grant::Model
  include Gemma::Grant::Attachable
  
  has_one_attached :avatar
end

# Upload a file
user = User.new(name: "John")
user.avatar = File.open("path/to/avatar.jpg")
user.save

# Access the attachment
if avatar = user.avatar
  puts avatar.url
  puts avatar.size
  puts avatar.mime_type
  puts avatar.original_filename
end

# Remove the attachment
user.avatar = nil
user.save
```

## Multiple File Attachments

Use `has_many_attached` for multiple file attachments:

```crystal
class Post < Grant::Model
  include Gemma::Grant::Attachable
  
  column id : Int64, primary: true
  column title : String
  column images_data : JSON::Any?
  
  has_many_attached :images
end

# Upload multiple files
post = Post.new(title: "My Post")
post.images = [
  File.open("image1.jpg"),
  File.open("image2.jpg")
]
post.save

# Access attachments
post.images.each do |image|
  puts image.url
end

# Add a single file to existing attachments
post.add_image(File.open("image3.jpg"))
post.save

# Remove a specific attachment
if image = post.images.first?
  post.remove_image(image)
  post.save
end

# Clear all attachments
post.clear_images
post.save
```

## Custom Uploaders

You can specify custom uploaders for more control:

```crystal
class AvatarUploader < Gemma
  # Custom location generation
  def generate_location(io : IO | UploadedFile, metadata, **options)
    name = super(io, metadata, **options)
    File.join("avatars", Time.utc.to_s("%Y/%m"), name)
  end
  
  finalize_plugins!
end

class User < Grant::Model
  include Gemma::Grant::Attachable
  
  # Use custom uploader
  has_one_attached :avatar, uploader: AvatarUploader
end
```

## Web Framework Integration

### With Amber

```crystal
class UsersController < ApplicationController
  def create
    user = User.new(user_params)
    
    # Handle file upload from form
    if avatar = params.files["avatar"]?
      user.avatar = avatar
    end
    
    if user.save
      redirect_to "/users/#{user.id}"
    else
      render "new.slang"
    end
  end
  
  def update
    user = User.find!(params["id"])
    
    # Handle avatar removal
    if params["remove_avatar"]?
      user.avatar = nil
    elsif avatar = params.files["avatar"]?
      user.avatar = avatar
    end
    
    if user.save
      redirect_to "/users/#{user.id}"
    else
      render "edit.slang"
    end
  end
end
```

### Form Example

```slang
form action="/users" method="post" enctype="multipart/form-data"
  div.field
    label for="avatar" Avatar
    input type="file" name="avatar" id="avatar"
  
  - if user.avatar
    div.current-avatar
      img src=user.avatar_url width="100"
      label
        input type="checkbox" name="remove_avatar" value="1"
        | Remove avatar
  
  button type="submit" Save
```

## Advanced Options

### Custom Column Names

```crystal
class Document < Grant::Model
  include Gemma::Grant::Attachable
  
  column id : Int64, primary: true
  column file_metadata : JSON::Any?
  
  # Specify custom column name
  has_one_attached :file, column_name: :file_metadata
end
```

### Attachment URLs with Options

```crystal
# Generate URL with custom options (depends on storage adapter)
user.avatar_url(public: true)
user.avatar_url(expires_in: 3600)  # For S3 presigned URLs
```

## Callbacks

The integration automatically handles:

- **Before save**: Promotes cached files to permanent storage
- **After save**: Persists attachment metadata to database
- **After destroy**: Deletes associated files from storage

## Testing

```crystal
describe User do
  it "handles avatar upload" do
    user = User.new(name: "Test User")
    
    # Simulate file upload
    file = File.tempfile("test") do |f|
      f.print("test content")
    end
    
    user.avatar = file
    user.save
    
    user.avatar.should_not be_nil
    user.avatar.not_nil!.size.should eq(12)
  end
end
```

## Troubleshooting

### Files Not Being Deleted

Ensure your model's `after_destroy` callbacks are being triggered. Grant should handle this automatically.

### JSON Parsing Errors

Make sure your database columns are properly typed as JSON or JSONB (PostgreSQL).

### File Upload Size Limits

Configure your web server and framework to handle the expected file sizes:

```crystal
# In Amber config
Amber::Server.configure do |settings|
  settings.max_request_size = 100.megabytes
end
```