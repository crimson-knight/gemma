# Gemma

[![GitHub release](https://img.shields.io/github/release/crimson-knight/gemma.svg)](https://github.com/crimson-knight/gemma/releases/)
[![GitHub license](https://img.shields.io/github/license/crimson-knight/gemma)](https://github.com/crimson-knight/gemma/blob/master/LICENSE)

Gemma is a toolkit for file attachments in Crystal applications. Heavily inspired by [Shrine for Ruby](https://shrinerb.com).

This is a fork from [JetRockets](https://github.com/jetrockets/shrine.cr)

## Installation

1. Add the dependency to your `shard.yml`:

   ```yaml
   dependencies:
     gemma:
       github: crimson-knight/gemma
   ```

2. Run `shards install`

## Usage

```crystal
require "gemma"
```

Gemma is under heavy development!

First of all, you should configure `Gemma`.

```crystal
Gemma.configure do |config|
  config.storages["cache"] = Storage::FileSystem.new("uploads", prefix: "cache")
  config.storages["store"] = Storage::FileSystem.new("uploads")
end
```

Now you can use `Gemma` directly to upload your files.

```crystal
Gemma.upload(file, "store")
```

`Gemma.upload` method supports additional argument just like Shrine for Ruby. For example we want our file to have a custom filename.

```crystal
Gemma.upload(file, "store", metadata: { "filename" => "foo.bar" })
```

### Custom uploaders

To implement custom uploader class just inherit it from `Gemma`. You can override `Gemma` methods to implement custom logic. Here is an example how to create a custom file location.

```crystal
class FileImport::AssetUploader < Gemma
  def generate_location(io : IO | UploadedFile, metadata, context, **options)
    name = super(io, metadata, **options)

    File.join("imports", context[:model].id.to_s, name)
  end
end

FileImport::AssetUploader.upload(file, "store", context: { model: YOUR_ORM_MODEL } })
```

### S3 storage

#### Creating a Client

```crystal
client = Awscr::S3::Client.new("region", "key", "secret")
```

For S3 compatible services, like DigitalOcean Spaces or Minio, you'll need to set a custom endpoint:

```crystal
client = Awscr::S3::Client.new("nyc3", "key", "secret", endpoint: "https://nyc3.digitaloceanspaces.com")
```

#### Create a S3 storage

The storage is initialized by providing your bucket and client:

```crystal
storage = Gemma::Storage::S3.new(bucket: "bucket_name", client: client, prefix: "prefix")
```

Sometimes you'll want to add additional upload options to all S3 uploads. You can do that by passing the :upload_options option:

```crystal
storage = Gemma::Storage::S3.new(bucket: "bucket_name", client: client, upload_options: { "x-amz-acl"=> "public-read" })
```

You can tell S3 storage to make uploads public:

```crystal
storage = Gemma::Storage::S3.new(bucket: "bucket_name", client: client, public: true)
```

### ORM usage example

#### Grant (Recommended - Full Support)

Grant ORM now has full integration support with comprehensive features:

```crystal
require "gemma/grant"

class User < Grant::Base
  include Gemma::Grant::Attachable
  
  column id : Int64, primary: true
  column name : String
  column avatar_data : JSON::Any?
  column documents_data : JSON::Any?
  
  # Single file attachment
  has_one_attached :avatar
  
  # Multiple file attachments  
  has_many_attached :documents
end

# Usage
user = User.new(name: "John")
user.avatar = File.open("avatar.jpg")
user.documents = [File.open("doc1.pdf"), File.open("doc2.pdf")]
user.save

# Access attachments
puts user.avatar_url
user.documents.each { |doc| puts doc.url }

# With validations
class ValidatedUser < Grant::Base
  include Gemma::Grant::Attachable
  include Gemma::Grant::AttachmentValidators
  
  has_one_attached :avatar
  
  validate_file_size_of :avatar, maximum: 5.megabytes
  validate_content_type_of :avatar, accept: ["image/jpeg", "image/png"]
end
```

See [GRANT_COMPLETE_GUIDE.md](GRANT_COMPLETE_GUIDE.md) for comprehensive documentation.

#### Granite

```crystal
class FileImport < Granite::Base
  connection pg
  table file_imports

  column id : Int64, primary: true
  column asset_data : Gemma::UploadedFile, converter: Granite::Converters::Json(Gemma::UploadedFile, JSON::Any)

  after_save do
    if @asset_changed && @asset_data
      @asset_data = FileImport::AssetUploader.store(@asset_data.not_nil!, move: true, context: { model: self })
      @asset_changed = false

      save!
    end
  end

  def asset=(upload : Amber::Router::File)
    @asset_data = FileImport::AssetUploader.cache(upload.file, metadata: { filename: upload.filename })
    @asset_changed = true
  end
end

```

#### Jennifer

```crystal
class FileImport < Jennifer::Model::Base
  @asset_changed : Bool | Nil

  with_timestamps

  mapping(
    id: Primary32,
    asset_data: JSON::Any?,
    created_at: Time?,
    updated_at: Time?
  )

  after_save :move_to_store

  def asset=(upload : Amber::Router::File)
    self.asset_data = JSON.parse(FileImport::AssetUploader.cache(upload.file, metadata: { filename: upload.filename }).to_json)
    asset_changed! if asset_data
  end

  def asset
    Gemma::UploadedFile.from_json(asset_data.not_nil!.to_json) if asset_data
  end

  def asset_changed?
    @asset_changed || false
  end

  private def asset_changed!
    @asset_changed = true
  end

  private def move_to_store
    if asset_changed?
      self.asset_data = JSON.parse(FileImport::AssetUploader.store(asset.not_nil!, move: true, context: { model: self }).to_json)
      @asset_changed = false
      save!
    end
  end
end

```

## Plugins

Gemma has a plugins interface similar to Shrine for Ruby. You can extend functionality of uploaders inherited from `Gemma` and also extend `UploadedFile` class.

### Determine MIME Type

The `DetermineMimeType` plugin is used to get mime type of uploaded file in several ways.

```crystal

require "gemma/plugins/determine_mime_type"

class Uploader < Gemma
  load_plugin(
    Gemma::Plugins::DetermineMimeType,
    analyzer: Gemma::Plugins::DetermineMimeType::Tools::File
  )

  finalize_plugins!
end
```

**Analyzers**

The following analyzers are accepted:

| Name          | Description                                                                                                                                                                                                         |
| ------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `File`        | (**Default**). Uses the file utility to determine the MIME type from file contents. It is installed by default on most operating systems.                                                                           |
| `Mime`        | Uses the [MIME.from_filename](https://crystal-lang.org/api/0.31.1/MIME.html) method to determine the MIME type from file.                                                                                           |
| `ContentType` | Retrieves the value of the `#content_type` attribute of the IO object. Note that this value normally comes from the "Content-Type" request header, so it's not guaranteed to hold the actual MIME type of the file. |

### Add Metadata

The `AddMetadata` plugin provides a convenient method for extracting and adding custom metadata values.

```crystal
require "base64"
require "gemma/plugins/add_metadata"

class Uploader < Gemma
  load_plugin(Gemma::Plugins::AddMetadata)

  add_metadata :signature, -> {
    Base64.encode(io.gets_to_end)
  }

  finalize_plugins!
end
```

The above will add `"signature"` to the metadata hash.

```crystal
image.metadata["signature"]
```

**Multiple values**

You can also extract multiple metadata values at once.

```crystal
class Uploader < Gemma
  load_plugin(Gemma::Plugins::AddMetadata)

  add_metadata :multiple_values, -> {
    text = io.gets_to_end

    Gemma::UploadedFile::MetadataType{
      "custom_1" => text,
      "custom_2" => text * 2
    }
  }

  finalize_plugins!
end
```

```crystal
image.metadata["custom_1"]
image.metadata["custom_2"]
```

### Store Dimensions

The `StoreDimensions` plugin extracts dimensions of uploaded images and stores them into the metadata. Additional dependency [https://github.com/jetrockets/fastimage.cr](https://github.com/jetrockets/fastimage.cr) needed for this plugin.

```crystal

require "fastimage"
require "gemma/plugins/store_dimensions"

class Uploader < Gemma
  load_plugin(Gemma::Plugins::StoreDimensions,
    analyzer: Gemma::Plugins::StoreDimensions::Tools::FastImage)

  finalize_plugins!
end
```

```crystal
image.metadata["width"]
image.metadata["height"]
```

**Analyzers**

The following analyzers are accepted:

| Name        | Description                                                                     |
| ----------- | ------------------------------------------------------------------------------- |
| `FastImage` | (**Default**) Uses the [FastImage](https://github.com/jetrockets/fastimage.cr). |
| `Identify`  | A built-in solution that wrapps ImageMagick's `identify` command.               |

## Feature Progress

In no particular order, features that have been implemented and are planned.
Items not marked as completed may have partial implementations.

- [x] Gemma
- [x] Gemma::UploadedFile
  - [ ] ==
  - [x] #original_filename
  - [x] #extension
  - [x] #size
  - [x] #mime_type
  - [x] #close
  - [x] #url
  - [x] #exists?
  - [x] #open
  - [x] #download
  - [x] #stream
  - [x] #replace
  - [x] #delete
- [x] Gemma::Attacher
- [ ] Gemma::Attachment
- [x] Gemma::Storage
  - [x] Gemma::Storage::Memory
  - [x] Gemma::Storage::FileSystem
  - [x] Gemma::Storage::S3
- [ ] Uploaders
  - [x] Custom uploaders
  - [ ] Derivatives
- [x] ORM adapters
  - [x] `Grant` [https://github.com/crimson-knight/grant](https://github.com/crimson-knight/grant) - **Full Support with Validations**
- [x] Plugins
- [ ] Background processing

## Contributing

1. Fork it (<https://github.com/crimson-knight/gemma/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

[See Gemma contributors](https://github.com/crimson-knight/gemma/graphs/contributors)
