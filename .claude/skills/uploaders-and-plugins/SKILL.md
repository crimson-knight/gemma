---
name: uploaders-and-plugins
description: Reference for creating custom Gemma uploaders and using the plugin system — covers DetermineMimeType, AddMetadata, StoreDimensions, and Column plugins, plus how to create new plugins.
user-invocable: false
---

# Custom Uploaders and Plugins

Gemma's uploader and plugin system provides extensibility at two levels: custom uploaders allow you to control file location and upload behavior, while plugins extend the core functionality with features like MIME type detection, metadata extraction, and image dimension analysis.

## Custom Uploaders

Custom uploaders inherit from `Gemma` and can override methods to customize upload behavior. The most common customization is `generate_location` to control where files are stored.

### Basic Custom Uploader

```crystal
class ImageUploader < Gemma
  # Override to customize file storage location
  def generate_location(io : IO | UploadedFile, metadata, **options)
    name = super(io, metadata, **options)
    File.join("images", Time.utc.to_s("%Y/%m"), name)
  end
end

# Use directly
uploaded = ImageUploader.upload(File.open("photo.jpg"), "store")
uploaded.url  # => "/uploads/images/2026/03/abc123.jpg"
```

The `generate_location` method receives:
- `io` — The IO object or UploadedFile being uploaded
- `metadata` — Hash with extracted metadata (filename, size, mime_type, and any custom fields)
- `**options` — Additional keyword options passed through the upload chain

The `super` call invokes `basic_location`, which generates a random hex filename preserving the original file extension.

### Context-Aware Uploader

When used with Grant integration, the uploader can access model context:

```crystal
class DocumentUploader < Gemma
  def generate_location(io : IO | UploadedFile, metadata, context, **options)
    name = super(io, metadata, **options)
    File.join("documents", context[:model].id.to_s, name)
  end
end

# Upload with context
DocumentUploader.upload(file, "store", context: { model: user })
```

### Using Custom Uploaders with Grant Models

Pass the `uploader:` option to `has_one_attached` or `has_many_attached`:

```crystal
class Article < Grant::Base
  include Gemma::Grant::Attachable

  column id : Int64, primary: true
  column title : String
  column cover_image_data : JSON::Any?
  column attachments_data : JSON::Any?

  has_one_attached :cover_image, uploader: ImageUploader
  has_many_attached :attachments, uploader: DocumentUploader
end
```

### Uploader Inheritance

Custom uploaders inherit from `Gemma` and automatically get:
- Their own `PLUGINS` array (plugins from the parent are inherited)
- Their own `Attacher` subclass
- All class methods (`upload`, `cache`, `store`, `find_storage`)
- All instance methods (`upload`, `generate_location`, `storage`)

```crystal
# Base uploader with shared plugins
class AppUploader < Gemma
  load_plugin(Gemma::Plugins::DetermineMimeType)
  finalize_plugins!
end

# Specialized uploaders inherit the plugin
class AvatarUploader < AppUploader
  def generate_location(io : IO | UploadedFile, metadata, **options)
    name = super(io, metadata, **options)
    File.join("avatars", name)
  end
end

# AvatarUploader automatically has DetermineMimeType
```

## Plugin System Overview

Gemma's plugin system uses Crystal macros to extend uploader classes. Plugins can inject methods at multiple levels:

| Module | Target | Description |
|--------|--------|-------------|
| `ClassMethods` | Uploader class | Extends the uploader with class-level methods |
| `InstanceMethods` | Uploader instances | Included in uploader instances (overrides like `extract_metadata`) |
| `FileClassMethods` | UploadedFile class | Extends the UploadedFile class |
| `FileMethods` | UploadedFile instances | Adds methods to UploadedFile instances (e.g., `width`, `height`) |
| `AttacherClassMethods` | Attacher class | Extends the Attacher class |
| `AttacherMethods` | Attacher instances | Adds methods to Attacher instances |

### Loading Plugins

Use the `load_plugin` macro inside your uploader class, followed by `finalize_plugins!`:

```crystal
class MyUploader < Gemma
  load_plugin(Gemma::Plugins::DetermineMimeType,
    analyzer: Gemma::Plugins::DetermineMimeType::Tools::File)
  load_plugin(Gemma::Plugins::StoreDimensions,
    analyzer: Gemma::Plugins::StoreDimensions::Tools::FastImage)

  finalize_plugins!
end
```

**Important rules:**
1. `finalize_plugins!` MUST be called after all `load_plugin` calls
2. A plugin cannot be loaded twice on the same uploader (raises at compile time)
3. Plugins loaded on a parent uploader are automatically inherited by child uploaders
4. Plugin options are passed as named arguments to `load_plugin`

## Built-in Plugins

### DetermineMimeType

Determines the MIME type of uploaded files using configurable analyzers, replacing the default behavior of reading the `Content-Type` header.

**Require:** `require "gemma/plugins/determine_mime_type"`

**Analyzers:**

| Analyzer | Enum Value | Description |
|----------|-----------|-------------|
| File | `Tools::File` | **(Default)** Uses the `file` command-line tool to detect MIME type from file content. Most reliable. |
| Mime | `Tools::Mime` | Uses Crystal's `MIME.from_filename?` to determine type from file extension. Fast but less reliable. |
| ContentType | `Tools::ContentType` | Reads the `content_type` attribute from the IO object (typically from the HTTP request header). Least reliable. |

**Usage:**

```crystal
require "gemma/plugins/determine_mime_type"

class MyUploader < Gemma
  # Use the file command (default and most accurate)
  load_plugin(Gemma::Plugins::DetermineMimeType,
    analyzer: Gemma::Plugins::DetermineMimeType::Tools::File)

  finalize_plugins!
end

# MIME type is automatically extracted during upload
uploaded = MyUploader.upload(File.open("photo.jpg"), "store")
uploaded.mime_type  # => "image/jpeg"
```

**How it works:** The plugin overrides `extract_mime_type` in `InstanceMethods`. During upload, `extract_metadata` calls this method, which delegates to the configured analyzer. The result is stored in `metadata["mime_type"]`.

### AddMetadata

Provides a declarative way to extract and add custom metadata values during upload.

**Require:** `require "gemma/plugins/add_metadata"`

**Usage — single value:**

```crystal
require "base64"
require "gemma/plugins/add_metadata"

class MyUploader < Gemma
  load_plugin(Gemma::Plugins::AddMetadata)

  # Add a single metadata field
  add_metadata :signature, -> {
    Base64.encode(io.gets_to_end)
  }

  finalize_plugins!
end

uploaded = MyUploader.upload(file, "store")
uploaded.metadata["signature"]  # => "base64-encoded-content..."
```

**Usage — multiple values at once:**

```crystal
class MyUploader < Gemma
  load_plugin(Gemma::Plugins::AddMetadata)

  add_metadata :checksums, -> {
    content = io.gets_to_end

    Gemma::UploadedFile::MetadataType{
      "md5"    => Digest::MD5.hexdigest(content),
      "sha256" => Digest::SHA256.hexdigest(content),
    }
  }

  finalize_plugins!
end

uploaded.metadata["md5"]     # => "d41d8cd98f00b204e9800998ecf8427e"
uploaded.metadata["sha256"]  # => "e3b0c44298fc1c149afb..."
```

**How it works:** The plugin defines `CUSTOM_METATADATA_FIELDS` (a compile-time hash) and overrides `extract_metadata` to call each registered proc. The IO is automatically rewound after each extraction. If the proc returns a `MetadataType` hash, all entries are merged; otherwise the result is stored under the specified key.

### StoreDimensions

Extracts width and height of uploaded images and stores them in metadata.

**Require:** `require "gemma/plugins/store_dimensions"` (also requires the `fastimage` shard)

**Dependency:** Add `fastimage` to your `shard.yml`:
```yaml
dependencies:
  fastimage:
    github: jetrockets/fastimage.cr
    version: ~> 1.2.1
```

**Analyzers:**

| Analyzer | Enum Value | Description |
|----------|-----------|-------------|
| FastImage | `Tools::FastImage` | **(Default)** Uses the FastImage library for fast dimension detection |
| Identify | `Tools::Identify` | Uses ImageMagick's `identify` command-line tool |

**Usage:**

```crystal
require "fastimage"
require "gemma/plugins/store_dimensions"

class ImageUploader < Gemma
  load_plugin(Gemma::Plugins::StoreDimensions,
    analyzer: Gemma::Plugins::StoreDimensions::Tools::FastImage)

  finalize_plugins!
end

uploaded = ImageUploader.upload(File.open("photo.jpg"), "store")
uploaded.metadata["width"]   # => 1920
uploaded.metadata["height"]  # => 1080
```

**FileMethods added to UploadedFile:**

The plugin adds convenience methods to UploadedFile instances:

```crystal
uploaded.width       # => 1920 (UInt16)
uploaded.height      # => 1080 (UInt16)
uploaded.dimensions  # => {1920, 1080} (Tuple(UInt16, UInt16))
```

### Column Plugin

Provides serialization support for storing attachment data in database columns. This is used internally by the Attacher for column-based persistence.

**Require:** `require "gemma/plugins/column"` (loaded automatically when needed)

**Usage:**

```crystal
class MyUploader < Gemma
  load_plugin(Gemma::Plugins::Column)
  finalize_plugins!
end

attacher = MyUploader::Attacher.from_column('{"id":"abc","storage_key":"store","metadata":{}}')
attacher.column_data  # => '{"id":"abc","storage_key":"store","metadata":{}}'
```

The default serializer is `Gemma::Plugins::Column::JsonSerializer`. You can create custom serializers by inheriting from `Gemma::Plugins::Column::BaseSerializer` and implementing `.dump` and `.load`.

## Combining Multiple Plugins

Plugins can be composed together. Load order matters only when plugins override the same methods (later plugins wrap earlier ones via `super`):

```crystal
require "gemma/plugins/determine_mime_type"
require "gemma/plugins/add_metadata"
require "gemma/plugins/store_dimensions"

class FullFeaturedUploader < Gemma
  # Detect MIME type from file content
  load_plugin(Gemma::Plugins::DetermineMimeType,
    analyzer: Gemma::Plugins::DetermineMimeType::Tools::File)

  # Extract image dimensions
  load_plugin(Gemma::Plugins::StoreDimensions,
    analyzer: Gemma::Plugins::StoreDimensions::Tools::FastImage)

  # Add custom metadata
  load_plugin(Gemma::Plugins::AddMetadata)
  add_metadata :uploaded_at, -> {
    Time.utc.to_s("%Y-%m-%dT%H:%M:%SZ")
  }

  finalize_plugins!

  def generate_location(io : IO | UploadedFile, metadata, **options)
    ext = File.extname(metadata["filename"].to_s) if metadata["filename"]?
    mime = metadata["mime_type"]?.try(&.to_s) || "unknown"
    category = mime.split("/").first  # "image", "application", etc.

    "#{category}/#{generate_uid(io)}#{ext}"
  end
end
```

## Creating a New Plugin

To create a custom plugin, define a module under `Gemma::Plugins` with the appropriate sub-modules:

```crystal
module Gemma::Plugins
  module Watermark
    # Optional: define default options
    DEFAULT_OPTIONS = {
      text: "Copyright",
    }

    # Methods added to the uploader class (extend)
    module ClassMethods
      def watermark_text
        plugin_settings.watermark[:text]
      end
    end

    # Methods added to uploader instances (include)
    module InstanceMethods
      # Override extract_metadata to add watermark info
      private def extract_metadata(io, **options) : Gemma::UploadedFile::MetadataType
        metadata = super
        metadata["watermarked"] = "true"
        metadata
      end
    end

    # Methods added to UploadedFile instances
    module FileMethods
      def watermarked?
        metadata["watermarked"]? == "true"
      end
    end
  end
end
```

**Using the custom plugin:**

```crystal
class WatermarkedUploader < Gemma
  load_plugin(Gemma::Plugins::Watermark, text: "My Company")
  finalize_plugins!
end

WatermarkedUploader.watermark_text           # => "My Company"
uploaded = WatermarkedUploader.upload(io, "store")
uploaded.watermarked?                         # => true
```

**Plugin module reference:**

| Module Name | Injection Point | Use When |
|-------------|----------------|----------|
| `ClassMethods` | `extend` on uploader class | Adding class-level helpers, configuration readers |
| `InstanceMethods` | `include` in uploader | Overriding `extract_metadata`, `extract_mime_type`, upload hooks |
| `FileClassMethods` | `extend` on UploadedFile | Adding class-level methods to UploadedFile |
| `FileMethods` | `include` in UploadedFile | Adding instance methods like `width`, `watermarked?` |
| `AttacherClassMethods` | `extend` on Attacher | Adding class-level Attacher methods |
| `AttacherMethods` | `include` in Attacher | Adding instance methods to Attacher |
| `DEFAULT_OPTIONS` | Constant | Provides defaults that are merged with user-supplied options |

**Accessing plugin settings at runtime:**

After calling `finalize_plugins!`, plugin options are accessible via:

```crystal
MyUploader.plugin_settings.all
# => [{name: "watermark", options: {text: "My Company"}}]

MyUploader.plugin_settings["watermark"]
# => {text: "My Company"}
```
