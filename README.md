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

Configure the storages once at boot (in an Amber app,
`config/initializers/gemma.cr`):

```crystal
Gemma.configure do |config|
  config.storages["cache"] = Gemma::Storage::FileSystem.new("uploads", prefix: "cache")
  config.storages["store"] = Gemma::Storage::FileSystem.new("uploads", prefix: "store")
end
```

Then upload any `IO` (a file, a request body, a socket) to a storage by
name. Gemma streams it once, counts its size and reads its MIME type from
the bytes:

```crystal
uploaded_file = Gemma.upload(file, "store")
uploaded_file.size      # => 753
uploaded_file.mime_type # => "image/png"
uploaded_file.url       # => "/uploads/store/0f1e...a9.png"
```

The client's filename and custom fields can be passed; Gemma sanitizes the
filename and ignores attempts to set `size`, `mime_type`, `width` or
`height`, which come from the file (unless an uploader opts in to the
client's claim for unrecognized bytes; see Determine MIME Type):

```crystal
Gemma.upload(file, "store", filename: "photo.png", metadata: {"album" => "trips"})
```

In an Amber controller, pass the multipart part itself so the client's
filename and `Content-Type` come along:

```crystal
Gemma.upload(params.files["avatar"], "cache")
```

A stored file is a value. Open it, download it to a tempfile, or store its
JSON (`{"id": ..., "storage_key": ..., "metadata": {...}}`) in a text column:

```crystal
uploaded_file.open(&.gets_to_end)
uploaded_file.download { |tempfile| tempfile.path }

json = uploaded_file.to_json
same_file = Gemma::UploadedFile.from_json(json)
```

### Custom uploaders

Subclass `Gemma::Uploader` and override its methods. This one limits the
size of uploads and stores them under a directory:

```crystal
class AvatarUploader < Gemma::Uploader
  def max_size : Int64?
    5_000_000_i64
  end

  def generate_location(metadata : Gemma::Metadata) : String
    File.join("avatars", super)
  end
end

AvatarUploader.upload(file, "store")
```

An upload past `max_size` raises `Gemma::FileTooLarge` while it streams, and
nothing is left in storage. `upload(io, "store", max_size: ...)` sets a limit
for one call.

### S3 storage

#### Creating a Client

Gemma talks to S3 itself: it signs requests with AWS Signature Version 4
(OpenSSL HMAC-SHA256 from the standard library) and uses `HTTP::Client`, so it
needs no XML library and no extra shard.

```crystal
client = Gemma::Storage::S3::Client.new("us-east-2", "key", "secret")
```

For S3 compatible services, like DigitalOcean Spaces or MinIO, set a custom endpoint:

```crystal
client = Gemma::Storage::S3::Client.new("nyc3", "key", "secret", endpoint: "https://nyc3.digitaloceanspaces.com")
client = Gemma::Storage::S3::Client.new("us-east-1", "key", "secret", endpoint: "http://localhost:9000")
```

The client addresses buckets in one of two styles:

- `:virtual_hosted` (`https://<bucket>.<endpoint host>/<key>`), the default for AWS and
  DigitalOcean Spaces. Spaces presigned URLs only work in this style.
- `:path` (`https://<endpoint host>/<bucket>/<key>`), the default for any other endpoint
  such as MinIO. Choose it on AWS for bucket names that contain dots.

```crystal
client = Gemma::Storage::S3::Client.new("us-east-2", "key", "secret", addressing_style: :path)
```

A request that fails raises `Gemma::Storage::S3::ResponseError`, whose message holds the
HTTP status and the raw response body (`#status_code`, `#response_body`).
`Gemma::Storage::S3#open` raises `Gemma::FileNotFound` for a missing object.

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

`#url` returns a presigned GET URL valid for one day; pass `expires_in:` (a `Time::Span`
or seconds) to change that:

```crystal
storage.url("photo.jpg", expires_in: 1.hour)
```

### ORM usage example

#### Grant

`require "gemma/grant"` adds attachments to Grant models. Each macro
declares its `<name>_data` column (TEXT, holding the file's JSON), so the
table needs that column and the model does not declare it.

<!-- The block below is compiled by spec/probes/json_any_probe_spec.cr. -->
```crystal
require "gemma/grant"

class User < Grant::Base
  include Gemma::Grant::Attachable
  include Gemma::Grant::AttachmentValidators

  column id : Int64, primary: true
  column name : String?

  # Single file attachment; declares `avatar_data`.
  has_one_attached :avatar

  # Multiple file attachments; declares `documents_data`.
  has_many_attached :documents

  validates_attachment_size_of :avatar, maximum: 5_000_000
  validates_attachment_type_of :avatar, accept: ["image/jpeg", "image/png"]
  validates_attachment_count_of :documents, maximum: 10
end

user = User.new(name: "John")
user.avatar = File.open("avatar.jpg")          # cached now
user.documents = [File.open("doc1.pdf"), File.open("doc2.pdf")]
user.save                                      # promoted, column written

user.avatar_url
user.documents.map(&.url)
```

The migration adds one TEXT column per attachment:

```sql
ALTER TABLE users ADD COLUMN avatar_data TEXT;
ALTER TABLE users ADD COLUMN documents_data TEXT;
```

What happens when:

- **Assigning** (`user.avatar = io`, an Amber multipart part, or a
  `Gemma::CachedFileReference` from a re-rendered form) uploads to the cache
  only. A reference is accepted only for a file the cache holds, and its size
  and type are read again from the bytes.
- **Saving** promotes the cached file to the store in `before_save` and
  writes the column in the same statement.
- **After the save commits**, the replaced file, removed files and the cached
  copy are deleted. If the save rolls back, or a callback raises, the
  promoted file is deleted and the stored one is kept.
- **`remove_document(file)`, `clear_documents`, `user.avatar = nil`** change
  only the record; files are deleted after the next save commits.
- **Destroying** deletes the stored files after the destroy commits.
- **Setting `avatar_data` directly** is refused at save, because it would
  skip the checks assignment makes.

A cached reference works like a bearer token: whoever holds its id can
attach that cached file. The ids are 128 random bits, so keep them in the
form that uploaded the file and out of logs and URLs. Files cached for a form
that is never saved stay in the cache; expire them with a storage lifecycle
rule on the cache prefix.

Validators (`validates_attachment_presence_of`, `_size_of`, `_type_of`,
`_dimensions_of`, `_count_of`) are Grant rules and take `on:`, `if:`,
`unless:` and `strict:`. A file whose size, type or dimensions Gemma could
not read fails the rule that needs them.

`has_many_attached :documents, singular: document_file` names the helpers
`add_document_file` and `remove_document_file`.

#### Other ORMs

Store the file's JSON in a text column and attach through
`Gemma::Attacher`, which caches an upload and promotes it to permanent
storage:

```crystal
attacher = Gemma::Attacher.new
attacher.assign(file)        # uploads to "cache"
attacher.promote_and_cleanup # copies to "store", deletes a replaced file
column_value = attacher.column_data

attacher = Gemma::Attacher.from_column(column_value)
attacher.file.try(&.url)
```

## Plugins

Plugins are modules an uploader includes. Without any, every upload records
its size (counted while it streams) and its MIME type (from Gemma's built-in
magic-byte sniffer, which needs no external command).

### Store Dimensions

Records the width and height of uploaded images. Files that are not images
are stored without dimensions.

```crystal
class ImageUploader < Gemma::Uploader
  include Gemma::Plugins::StoreDimensions
end

image = ImageUploader.upload(file, "store")
image.width      # => 300 (Int32?)
image.height     # => 300
image.dimensions # => {300, 300}
```

| Tool       | Description |
| ---------- | ----------- |
| `Header`   | (**Default**) Gemma's header reader for PNG, GIF, JPEG (baseline and progressive), WebP and BMP. No external command. |
| `Identify` | Runs ImageMagick's `identify` on the upload's first bytes. Opt-in; it needs ImageMagick installed. |

Choose a tool by overriding the class method:

```crystal
class PosterUploader < Gemma::Uploader
  include Gemma::Plugins::StoreDimensions

  def self.dimensions_tool : Gemma::Plugins::StoreDimensions::Tools
    Gemma::Plugins::StoreDimensions::Tools::Identify
  end
end

PosterUploader.dimensions_tool # => Identify
```

### Determine MIME Type

Chooses how the MIME type is detected.

```crystal
class DocumentUploader < Gemma::Uploader
  include Gemma::Plugins::DetermineMimeType

  def self.mime_type_tool : Gemma::Plugins::DetermineMimeType::Tools
    Gemma::Plugins::DetermineMimeType::Tools::File
  end
end

DocumentUploader.mime_type_tool             # => File
DocumentUploader.upload(file, "store").mime_type # => "application/pdf"
```

| Tool          | Description |
| ------------- | ----------- |
| `MagicBytes`  | (**Default**) Gemma's built-in sniffer: JPEG, PNG, GIF, WebP, BMP, TIFF, HEIC/HEIF, AVIF, SVG, PDF, MP3, M4A, WAV, FLAC, Ogg, MP4, QuickTime, WebM, ZIP and UTF-8 text. Anything else gives `nil`. |
| `File`        | Runs the `file` command on the upload's first bytes. Opt-in; it needs `file` installed. |
| `Mime`        | The client filename's extension, through `MIME.from_filename?`. |
| `ContentType` | The client's declared `Content-Type`. |

`Mime` and `ContentType` are the client's claims, so Gemma uses them only for
bytes the sniffer does not recognize, and answers `application/octet-stream`
instead of a type a browser runs (HTML, XHTML, XML, SVG, JavaScript).

### Custom metadata

Override `custom_metadata` to store your own fields. It reads the upload's
first bytes (`Gemma::SNIFF_BYTES`, 256 KiB) and sees the metadata found so
far. Built-in fields (`size`, `mime_type`, `width`, `height`, `filename`)
always come from the file and cannot be set this way.

```crystal
require "digest/sha256"

class SignedUploader < Gemma::Uploader
  def custom_metadata(io : IO, metadata : Gemma::Metadata) : Hash(String, String)
    {"signature" => Digest::SHA256.hexdigest(io.getb_to_end)}
  end
end

signed = SignedUploader.upload(file, "store")
signed.metadata.extra["signature"]
```

### Upgrading from Gemma 0.6 plugins

`load_plugin` and `finalize_plugins!` were removed; using them is a compile
error that names the replacement. `include Gemma::Plugins::StoreDimensions`
replaces `load_plugin(Gemma::Plugins::StoreDimensions, ...)`, a
`custom_metadata` override replaces `AddMetadata` (it runs after the
plugins, so it sees `width` and `height`), and the `Column` plugin's
methods are built into `Gemma::Attacher` and read and write the
`UploadedFile` JSON. An app that stored columns with its own
`column_serializer` overrides `load_column` and `column_data` in its
uploader's attacher:

```crystal
class LegacyUploader < Gemma::Uploader
  class Attacher
    def column_data : String?
      file.try { |stored| "#{stored.storage_key}:#{stored.id}" }
    end

    def load_column(data : String) : Gemma::UploadedFile?
      storage_key, id = data.split(':', 2)
      load_data(Gemma::UploadedFile.new(id, storage_key))
    end
  end
end

LegacyUploader::Attacher.from_column("store:a1b2.png").column_data
```

## Feature Progress

In no particular order, features that have been implemented and are planned.
Items not marked as completed may have partial implementations.

- [x] Gemma
- [x] Gemma::UploadedFile
  - [x] ==
  - [x] #original_filename
  - [x] #extension
  - [x] #size
  - [x] #mime_type
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
