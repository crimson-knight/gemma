---
name: grant-integration
description: Complete reference for integrating Gemma file attachments with Grant ORM models, including attachment macros, column conventions, validations, URL access, file replacement, and Amber framework integration.
user-invocable: false
---

# Grant ORM Integration

Gemma provides full ActiveStorage-like integration with the Grant ORM through the `Gemma::Grant::Attachable` and `Gemma::Grant::AttachmentValidators` modules. This integration handles the complete attachment lifecycle: caching, promoting, persisting, replacing, and destroying files.

## Setup Requirements

**1. Require the Grant integration module:**

```crystal
require "gemma"
require "gemma/grant"
```

The `require "gemma/grant"` statement loads `src/gemma/grant.cr`, which in turn requires `src/gemma/grant/attachable.cr` and `src/gemma/grant/validators.cr`.

**2. Include Attachable in your model:**

```crystal
class User < Grant::Base
  include Gemma::Grant::Attachable

  self.connection_name = "primary"
  self.table_name = "users"

  column id : Int64, primary: true
  column name : String
  column avatar_data : JSON::Any?

  has_one_attached :avatar
end
```

**3. Ensure Gemma storage is configured** (see storage-configuration skill).

## JSON Column Naming Convention

Gemma stores attachment metadata in JSON columns on your model's table. The column name MUST follow this convention:

```
<attachment_name>_data
```

Examples:
- `has_one_attached :avatar` expects column `avatar_data : JSON::Any?`
- `has_one_attached :featured_image` expects column `featured_image_data : JSON::Any?`
- `has_many_attached :documents` expects column `documents_data : JSON::Any?`
- `has_many_attached :images` expects column `images_data : JSON::Any?`

The column type should always be `JSON::Any?` (nullable). In your database:
- **PostgreSQL/MySQL**: Use a `JSON` or `JSONB` column type
- **SQLite**: Use a `TEXT` column type

**Database migration example (PostgreSQL):**

```sql
CREATE TABLE users (
  id BIGSERIAL PRIMARY KEY,
  name VARCHAR(255) NOT NULL,
  avatar_data JSONB,
  documents_data JSONB,
  created_at TIMESTAMP,
  updated_at TIMESTAMP
);
```

## has_one_attached Macro

Defines a single file attachment on a Grant model.

**Signature:**
```crystal
has_one_attached(name, uploader = Gemma)
```

**Parameters:**
- `name` — Symbol name of the attachment (e.g., `:avatar`)
- `uploader` — Uploader class to use (defaults to `Gemma`; can be a custom uploader)

**Generated methods:**

| Method | Return Type | Description |
|--------|-------------|-------------|
| `avatar=(value : IO \| Nil)` | — | Assigns a file (IO) or removes attachment (nil) |
| `avatar=(value : String \| Hash)` | — | Sets from cached JSON/Hash data |
| `avatar` | `Gemma::UploadedFile?` | Returns the attached file, or nil |
| `avatar_url(**options)` | `String?` | Returns the file URL, or nil if no file attached |
| `avatar_changed?` | `Bool` | Whether the attachment was modified since last save |

**Generated callbacks:**

The macro registers three Grant callbacks automatically:
- `before_save` — Promotes cached file to permanent storage
- `after_save` — Persists file data to the JSON column, deletes replaced files
- `after_destroy` — Deletes the attached file from storage

**Example:**

```crystal
class User < Grant::Base
  include Gemma::Grant::Attachable

  column id : Int64, primary: true
  column name : String
  column avatar_data : JSON::Any?

  has_one_attached :avatar
end

# Assign and save
user = User.new(name: "Alice")
user.avatar = File.open("photo.jpg")
user.avatar_changed?  # => true
user.save

# Access
user.avatar           # => #<Gemma::UploadedFile>
user.avatar_url       # => "/uploads/abc123.jpg"

# Replace (old file is automatically deleted on save)
user.avatar = File.open("new_photo.jpg")
user.save

# Remove
user.avatar = nil
user.save
user.avatar           # => nil
```

**With custom uploader:**

```crystal
class ImageUploader < Gemma
  def generate_location(io : IO | UploadedFile, metadata, **options)
    name = super(io, metadata, **options)
    File.join("avatars", name)
  end
end

class User < Grant::Base
  include Gemma::Grant::Attachable

  column id : Int64, primary: true
  column avatar_data : JSON::Any?

  has_one_attached :avatar, uploader: ImageUploader
end
```

## has_many_attached Macro

Defines a collection of file attachments on a Grant model.

**Signature:**
```crystal
has_many_attached(name, uploader = Gemma)
```

**Parameters:**
- `name` — Symbol name of the attachment collection (e.g., `:documents`). Should be plural.
- `uploader` — Uploader class to use (defaults to `Gemma`)

**Singular name derivation:** The macro derives a singular name by stripping the trailing "s" from the collection name. For example, `:documents` becomes `document`, `:images` becomes `image`. This singular name is used for `add_<singular>` and `remove_<singular>` methods.

**Generated methods:**

| Method | Return Type | Description |
|--------|-------------|-------------|
| `documents=(values : Array(IO))` | — | Replaces all attachments with new files |
| `documents=(values : Array(String \| Hash))` | — | Sets from cached JSON/Hash data array |
| `documents` | `Array(Gemma::UploadedFile)` | Returns all attached files |
| `add_document(value : IO)` | — | Adds a single file to the collection |
| `remove_document(file : Gemma::UploadedFile)` | — | Removes and deletes a specific file |
| `clear_documents` | — | Removes and deletes all attached files |
| `documents_changed?` | `Bool` | Whether the collection was modified since last save |

**Generated callbacks:**

Same as `has_one_attached`: `before_save` promotes all cached files, `after_save` persists data, `after_destroy` cleans up all files.

**Example:**

```crystal
class Product < Grant::Base
  include Gemma::Grant::Attachable

  column id : Int64, primary: true
  column name : String
  column images_data : JSON::Any?

  has_many_attached :images
end

# Assign multiple files at once
product = Product.new(name: "Widget")
product.images = [
  File.open("front.jpg"),
  File.open("back.jpg"),
  File.open("side.jpg")
]
product.save

# Iterate
product.images.each do |image|
  puts image.url
  puts image.original_filename
end

# Add a single image
product.add_image(File.open("detail.jpg"))
product.save

# Remove a specific image
if target = product.images.first?
  product.remove_image(target)
  product.save
end

# Clear all images
product.clear_images
product.save
```

## Attachment Validators

The `Gemma::Grant::AttachmentValidators` module provides declarative validation macros for attachments. Include it alongside `Attachable`:

```crystal
class User < Grant::Base
  include Gemma::Grant::Attachable
  include Gemma::Grant::AttachmentValidators

  column id : Int64, primary: true
  column avatar_data : JSON::Any?
  column documents_data : JSON::Any?

  has_one_attached :avatar
  has_many_attached :documents

  # Validations
  validate_file_size_of :avatar, maximum: 5_000_000
  validate_content_type_of :avatar, accept: ["image/jpeg", "image/png", "image/webp"]
  validate_presence_of :avatar
  validate_collection_size_of :documents, maximum: 10, minimum: 1
end
```

### validate_file_size_of

Validates the byte size of an attached file.

```crystal
validate_file_size_of(name, maximum = nil, minimum = nil, message = nil)
```

| Parameter | Type | Description |
|-----------|------|-------------|
| `name` | Symbol | Attachment name (e.g., `:avatar`) |
| `maximum` | Int? | Maximum allowed size in bytes |
| `minimum` | Int? | Minimum allowed size in bytes |
| `message` | String? | Custom error message (overrides default) |

```crystal
validate_file_size_of :avatar, maximum: 5_000_000                    # Max 5MB
validate_file_size_of :avatar, minimum: 1024                         # Min 1KB
validate_file_size_of :avatar, minimum: 1024, maximum: 10_000_000    # Between 1KB and 10MB
validate_file_size_of :avatar, maximum: 2_000_000, message: "Avatar must be under 2MB"
```

### validate_content_type_of

Validates the MIME type of an attached file. Supports exact matches and wildcard patterns.

```crystal
validate_content_type_of(name, accept = nil, reject = nil, message = nil)
```

| Parameter | Type | Description |
|-----------|------|-------------|
| `name` | Symbol | Attachment name |
| `accept` | Array(String)? | Allowed MIME types (whitelist) |
| `reject` | Array(String)? | Forbidden MIME types (blacklist) |
| `message` | String? | Custom error message |

Wildcard support: Use `*` in patterns (e.g., `"image/*"` matches any image type).

```crystal
validate_content_type_of :avatar, accept: ["image/jpeg", "image/png"]
validate_content_type_of :avatar, accept: ["image/*"]                    # Any image type
validate_content_type_of :document, reject: ["application/x-executable"]
validate_content_type_of :avatar, accept: ["image/jpeg"], message: "must be a JPEG image"
```

### validate_presence_of

Validates that an attachment is present (not nil).

```crystal
validate_presence_of(name, message = nil)
```

```crystal
validate_presence_of :avatar
validate_presence_of :avatar, message: "Please upload a profile picture"
```

### validate_dimensions_of

Validates image dimensions. Requires the `StoreDimensions` plugin to populate width/height metadata.

```crystal
validate_dimensions_of(name, width = nil, height = nil, message = nil)
```

| Parameter | Type | Description |
|-----------|------|-------------|
| `name` | Symbol | Attachment name |
| `width` | Int \| Range? | Required width or width range |
| `height` | Int \| Range? | Required height or height range |
| `message` | String? | Custom error message |

```crystal
validate_dimensions_of :avatar, width: 200..2000, height: 200..2000
validate_dimensions_of :banner, width: 1200, height: 400              # Exact dimensions
validate_dimensions_of :icon, width: 64..512, height: 64..512
```

### validate_collection_size_of

Validates the number of files in a `has_many_attached` collection.

```crystal
validate_collection_size_of(name, maximum = nil, minimum = nil, message = nil)
```

```crystal
validate_collection_size_of :documents, maximum: 10
validate_collection_size_of :images, minimum: 1, maximum: 20
validate_collection_size_of :attachments, minimum: 1, message: "At least one attachment is required"
```

## Accessing Attachment URLs

```crystal
# Single attachment
user.avatar_url                              # => "/uploads/abc123.jpg" or presigned S3 URL

# With options (forwarded to storage)
user.avatar_url(host: "https://cdn.example.com")

# Via the UploadedFile object directly
if file = user.avatar
  file.url                                   # Same as avatar_url
  file.url(host: "https://cdn.example.com")
end

# Multiple attachments
product.images.each do |image|
  puts image.url
end

# Check if file exists on storage
user.avatar.try(&.exists?)  # => true/false
```

## Replacing and Removing Attachments

**Replacing a single attachment:**
When you assign a new file to a `has_one_attached` field, the old file is tracked. On `save`, the `after_save` callback deletes the previous file from storage.

```crystal
user.avatar = File.open("old.jpg")
user.save

user.avatar = File.open("new.jpg")  # Old file tracked for deletion
user.save                            # Old file deleted, new file persisted
```

**Removing a single attachment:**
```crystal
user.avatar = nil
user.save  # File deleted from storage, column set to nil
```

**Working with multiple attachments:**
```crystal
# Replace entire collection
product.images = [File.open("new1.jpg"), File.open("new2.jpg")]
product.save

# Remove one file
product.remove_image(product.images.first!)
product.save

# Clear all
product.clear_images
product.save
```

## Amber Framework File Parameter Handling

In an Amber controller, uploaded files come from `params.files`:

```crystal
class UsersController < ApplicationController
  def create
    user = User.new(user_params)

    # Single file upload
    if avatar_file = params.files["user[avatar]"]?
      user.avatar = avatar_file.file
    end

    if user.save
      redirect_to "/users/#{user.id}"
    else
      render "new.ecr"
    end
  end

  def update
    user = User.find!(params["id"])

    # Remove avatar if checkbox checked
    if params["remove_avatar"]?
      user.avatar = nil
    elsif avatar_file = params.files["user[avatar]"]?
      user.avatar = avatar_file.file
    end

    # Multiple file uploads
    if doc_files = params.files.select("user[documents][]")
      doc_files.each do |upload|
        user.add_document(upload.file)
      end
    end

    if user.save
      redirect_to "/users/#{user.id}"
    else
      render "edit.ecr"
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

**Form template (ECR):**
```html
<form action="/users" method="post" enctype="multipart/form-data">
  <%= csrf_tag %>
  <input type="file" name="user[avatar]" accept="image/*">
  <input type="file" name="user[documents][]" multiple>
  <button type="submit">Create</button>
</form>
```

## Complete Model Example

Here is a full example combining all features:

```crystal
require "gemma"
require "gemma/grant"
require "gemma/plugins/determine_mime_type"
require "gemma/plugins/store_dimensions"

# Custom uploader for images
class AvatarUploader < Gemma
  load_plugin(Gemma::Plugins::DetermineMimeType,
    analyzer: Gemma::Plugins::DetermineMimeType::Tools::File)
  load_plugin(Gemma::Plugins::StoreDimensions,
    analyzer: Gemma::Plugins::StoreDimensions::Tools::FastImage)

  finalize_plugins!

  def generate_location(io : IO | UploadedFile, metadata, **options)
    name = super(io, metadata, **options)
    File.join("avatars", name)
  end
end

class User < Grant::Base
  include Gemma::Grant::Attachable
  include Gemma::Grant::AttachmentValidators

  self.connection_name = "primary"
  self.table_name = "users"

  column id : Int64, primary: true
  column email : String
  column name : String?
  column avatar_data : JSON::Any?
  column documents_data : JSON::Any?
  column created_at : Time?
  column updated_at : Time?

  has_one_attached :avatar, uploader: AvatarUploader
  has_many_attached :documents

  # Validations
  validate_file_size_of :avatar, maximum: 5_000_000
  validate_content_type_of :avatar, accept: ["image/jpeg", "image/png", "image/webp"]
  validate_dimensions_of :avatar, width: 100..4000, height: 100..4000
  validate_collection_size_of :documents, maximum: 20
end
```

## Testing Grant Attachments

Use Memory storage for fast, isolated tests:

```crystal
require "spectator"

Spectator.describe User do
  before_each do
    Gemma.configure do |config|
      config.storages["cache"] = Gemma::Storage::Memory.new
      config.storages["store"] = Gemma::Storage::Memory.new
    end
  end

  it "attaches an avatar" do
    user = User.new(email: "test@example.com")
    user.avatar = IO::Memory.new("fake image data")
    user.avatar_changed?.should be_true
    expect(user.avatar).not_to be_nil
  end

  it "returns nil when no avatar attached" do
    user = User.new(email: "test@example.com")
    expect(user.avatar).to be_nil
    expect(user.avatar_url).to be_nil
  end
end
```
