---
name: storage-configuration
description: Comprehensive reference for configuring Gemma storage backends — FileSystem, Memory, and S3 — including the cache/store pattern and creating custom storage adapters.
user-invocable: false
---

# Gemma Storage Configuration

Gemma uses a dual-storage architecture inspired by Shrine for Ruby. Files are first uploaded to a temporary "cache" storage, then promoted to permanent "store" storage when the model is saved. This two-step pattern ensures that failed uploads or validation errors do not leave orphaned files in permanent storage.

## Configuring Storage

Storage configuration uses Habitat and must be done before any uploads. Typically this goes in an initializer file (e.g., `config/initializers/gemma.cr`):

```crystal
require "gemma"

Gemma.configure do |config|
  config.storages["cache"] = Gemma::Storage::FileSystem.new("uploads", prefix: "cache")
  config.storages["store"] = Gemma::Storage::FileSystem.new("uploads")
end
```

The keys "cache" and "store" are expected by Gemma's `Attacher` class. You can add additional named storages for specialized purposes.

## FileSystem Storage

The `Gemma::Storage::FileSystem` adapter stores files on the local filesystem. It is the simplest backend and works well for development and single-server deployments.

**Constructor signature:**
```crystal
Gemma::Storage::FileSystem.new(
  directory : String,
  prefix : String? = nil,
  clean : Bool = true,
  permissions : Int = 0o644,
  directory_permissions : Int = 0o755
)
```

**Parameters:**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `directory` | `String` | (required) | Base directory for file storage. Created automatically if it does not exist. |
| `prefix` | `String?` | `nil` | Subdirectory within `directory`. Included in generated URLs. Useful for separating cache from store. |
| `clean` | `Bool` | `true` | Automatically delete empty parent directories when a file is removed. Set to `false` if cleanup causes filesystem load. |
| `permissions` | `Int` | `0o644` | UNIX permissions applied to uploaded files. |
| `directory_permissions` | `Int` | `0o755` | UNIX permissions applied to created directories. |

**Examples:**

```crystal
# Basic setup — files stored in ./uploads/
store = Gemma::Storage::FileSystem.new("uploads")

# With prefix — files stored in ./uploads/cache/
cache = Gemma::Storage::FileSystem.new("uploads", prefix: "cache")

# Custom permissions
store = Gemma::Storage::FileSystem.new("uploads",
  permissions: 0o600,
  directory_permissions: 0o700
)

# Disable empty directory cleanup
store = Gemma::Storage::FileSystem.new("uploads", clean: false)
```

**URL generation:**
- Without prefix: returns the full filesystem path (e.g., `/path/to/uploads/abc123.jpg`)
- With prefix: returns a relative path including the prefix (e.g., `/cache/abc123.jpg`)
- An optional `host:` parameter can be passed to `url()` to prepend a hostname

```crystal
file = Gemma.upload(io, "store")
file.url                              # => "/uploads/abc123.jpg"
file.url(host: "https://cdn.example.com")  # => "https://cdn.example.com/uploads/abc123.jpg"
```

## Memory Storage

The `Gemma::Storage::Memory` adapter stores files in a simple in-memory hash. It is designed for testing — fast, requires no filesystem access, and easy to reset between tests.

**Constructor signature:**
```crystal
Gemma::Storage::Memory.new
```

No configuration parameters. Files are stored in an internal `Hash(String, String)`.

**Key methods:**

| Method | Description |
|--------|-------------|
| `store` | Returns the internal `Hash(String, String)` for inspection |
| `clear!` | Empties all stored files — call between tests for isolation |
| `delete_prefixed(prefix)` | Deletes all files whose keys start with the given prefix |
| `url(id)` | Returns `"memory://#{id}"` |

**Testing example:**

```crystal
require "gemma"

# Configure for tests
Gemma.configure do |config|
  config.storages["cache"] = Gemma::Storage::Memory.new
  config.storages["store"] = Gemma::Storage::Memory.new
end

# In test setup / teardown
before_each do
  Gemma.settings.storages["cache"].as(Gemma::Storage::Memory).clear!
  Gemma.settings.storages["store"].as(Gemma::Storage::Memory).clear!
end

# Verify uploads in tests
store = Gemma.settings.storages["store"].as(Gemma::Storage::Memory)
uploaded = Gemma.upload(IO::Memory.new("test content"), "store")
store.store.has_key?(uploaded.id).should be_true
```

## S3 Storage

The `Gemma::Storage::S3` adapter stores files on Amazon S3 or any S3-compatible service (DigitalOcean Spaces, Minio, Backblaze B2, etc.).

**Dependencies:** Requires the `awscr-s3` shard (included as a Gemma dependency).

**Constructor signature:**
```crystal
Gemma::Storage::S3.new(
  bucket : String,
  client : Awscr::S3::Client?,
  prefix : String? = nil,
  upload_options : Hash(String, String) = Hash(String, String).new,
  public : Bool = false
)
```

**Parameters:**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `bucket` | `String` | (required) | Name of the S3 bucket |
| `client` | `Awscr::S3::Client?` | (required) | Pre-configured S3 client instance |
| `prefix` | `String?` | `nil` | Key prefix ("directory") inside the bucket |
| `upload_options` | `Hash(String, String)` | `{}` | Additional headers applied to every upload (e.g., ACL, cache-control) |
| `public` | `Bool` | `false` | When `true`, adds `"x-amz-acl" => "public-read"` to all uploads |

**AWS S3 example:**

```crystal
require "awscr-s3"

client = Awscr::S3::Client.new(
  "us-east-1",
  ENV["AWS_ACCESS_KEY_ID"],
  ENV["AWS_SECRET_ACCESS_KEY"]
)

Gemma.configure do |config|
  config.storages["cache"] = Gemma::Storage::S3.new(
    bucket: "my-app-uploads",
    client: client,
    prefix: "cache"
  )
  config.storages["store"] = Gemma::Storage::S3.new(
    bucket: "my-app-uploads",
    client: client,
    prefix: "store",
    public: true
  )
end
```

**DigitalOcean Spaces example:**

```crystal
client = Awscr::S3::Client.new(
  "nyc3",
  ENV["DO_SPACES_KEY"],
  ENV["DO_SPACES_SECRET"],
  endpoint: "https://nyc3.digitaloceanspaces.com"
)

Gemma.configure do |config|
  config.storages["store"] = Gemma::Storage::S3.new(
    bucket: "my-space",
    client: client,
    public: true
  )
end
```

**Minio (self-hosted) example:**

```crystal
client = Awscr::S3::Client.new(
  "us-east-1",
  "minioadmin",
  "minioadmin",
  endpoint: "http://localhost:9000"
)

Gemma.configure do |config|
  config.storages["store"] = Gemma::Storage::S3.new(
    bucket: "uploads",
    client: client
  )
end
```

**Custom upload options:**

```crystal
# Add cache-control headers and ACL to every upload
store = Gemma::Storage::S3.new(
  bucket: "my-bucket",
  client: client,
  upload_options: {
    "x-amz-acl"       => "public-read",
    "Cache-Control"    => "max-age=31536000",
  }
)
```

**URL generation:** S3 storage generates presigned URLs by default, which include authentication parameters and an expiration time. This is handled internally by the `awscr-s3` library.

## Cache/Store Pattern

The cache/store pattern is central to Gemma's upload lifecycle:

1. **Cache phase**: When a file is assigned to a model (`user.avatar = file`), it is uploaded to the "cache" storage. This is a temporary holding area.
2. **Store phase**: When the model is saved, a `before_save` callback promotes the file from "cache" to "store" (permanent storage). The `after_save` callback persists the updated file data to the JSON column.
3. **Cleanup**: When a file is replaced or the model is destroyed, the old file is deleted from storage.

This pattern ensures:
- Failed validations do not leave files in permanent storage
- File data is only persisted after a successful save
- Replacing attachments automatically cleans up old files

## Creating a Custom Storage Adapter

To create a custom storage backend, inherit from `Gemma::Storage::Base` and implement all abstract methods:

```crystal
class Gemma::Storage::CustomBackend < Gemma::Storage::Base
  def initialize(@connection_string : String)
    # Initialize your storage connection
  end

  # Upload an IO or UploadedFile to the given location
  def upload(io : IO | UploadedFile, id : String, move = false, **options)
    content = io.is_a?(UploadedFile) ? io.storage.open(io.id).gets_to_end : io.gets_to_end
    # Store content at id in your backend
  end

  # Return an IO object for reading the file
  def open(id : String, **options) : IO
    # Retrieve file content and return as IO
    IO::Memory.new(retrieve_content(id))
  end

  # Return a URL string for the file
  def url(id : String, **options) : String
    "https://my-backend.example.com/files/#{id}"
  end

  # Return whether the file exists
  def exists?(id : String) : Bool
    # Check existence in your backend
  end

  # Delete the file
  def delete(id : String)
    # Remove file from your backend
  end

  # Clean up empty paths (can be a no-op for non-hierarchical backends)
  def clean(path : String)
    # Optional cleanup logic
  end
end
```

Register your custom storage like any other backend:

```crystal
Gemma.configure do |config|
  config.storages["store"] = Gemma::Storage::CustomBackend.new("connection-string")
end
```

## Environment-Specific Configuration

A common pattern is to use different storage backends per environment:

```crystal
Gemma.configure do |config|
  if Amber.env.test?
    config.storages["cache"] = Gemma::Storage::Memory.new
    config.storages["store"] = Gemma::Storage::Memory.new
  elsif Amber.env.development?
    config.storages["cache"] = Gemma::Storage::FileSystem.new("uploads", prefix: "cache")
    config.storages["store"] = Gemma::Storage::FileSystem.new("uploads")
  else
    client = Awscr::S3::Client.new(
      ENV["AWS_REGION"],
      ENV["AWS_ACCESS_KEY_ID"],
      ENV["AWS_SECRET_ACCESS_KEY"]
    )
    config.storages["cache"] = Gemma::Storage::S3.new(
      bucket: ENV["S3_BUCKET"], client: client, prefix: "cache"
    )
    config.storages["store"] = Gemma::Storage::S3.new(
      bucket: ENV["S3_BUCKET"], client: client, prefix: "store", public: true
    )
  end
end
```
