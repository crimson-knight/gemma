# CLAUDE.md

## Project Overview

Gemma is a Crystal file attachment toolkit inspired by Ruby's Shrine gem. It provides file upload, storage, and management with multiple storage backends (FileSystem, Memory, S3), full Grant ORM integration via `has_one_attached`/`has_many_attached` macros, a validation system (file size, content type, dimensions, presence), a plugin architecture for extensibility, and custom uploader support. Version 0.6.5, licensed MIT.

## Build and Test Commands

| Command | Description |
|---------|-------------|
| `shards install` | Install dependencies |
| `crystal spec` | Run all tests (Spectator framework) |
| `crystal spec spec/gemma/grant/` | Run Grant integration tests |
| `crystal spec --example "UploadedFile"` | Run tests matching a pattern |
| `crystal spec --verbose` | Run tests with verbose output |
| `./bin/ameba` | Run Ameba linter |
| `./bin/ameba src/gemma/grant/attachable.cr` | Lint specific file |
| `crystal tool format` | Auto-format source code |
| `crystal tool format --check` | Check formatting without changing files |
| `crystal build src/gemma.cr --release` | Build for release |

## Key Directories

| Path | Contents |
|------|----------|
| `src/gemma.cr` | Main Gemma class — core upload logic, plugin system macros, ClassMethods/InstanceMethods |
| `src/gemma/uploaded_file.cr` | UploadedFile — JSON-serializable file representation with metadata, IO operations |
| `src/gemma/attacher.cr` | Attacher — manages attachment lifecycle, cache-to-store promotion, dirty tracking |
| `src/gemma/storage/base.cr` | Abstract base class for storage adapters (upload, open, exists?, delete, url, clean) |
| `src/gemma/storage/file_system.cr` | FileSystem storage — local disk with directory, prefix, permissions, cleanup |
| `src/gemma/storage/memory.cr` | Memory storage — in-memory hash for testing, with clear! and delete_prefixed |
| `src/gemma/storage/s3.cr` | S3 storage — AWS S3 and compatible services (bucket, client, prefix, public, upload_options) |
| `src/gemma/grant/attachable.cr` | Grant ORM integration — has_one_attached / has_many_attached macros with callbacks |
| `src/gemma/grant/validators.cr` | Validation macros — file size, content type, presence, dimensions, collection size |
| `src/gemma/plugins/determine_mime_type.cr` | Plugin: MIME type detection (File, Mime, ContentType analyzers) |
| `src/gemma/plugins/add_metadata.cr` | Plugin: custom metadata extraction via add_metadata macro |
| `src/gemma/plugins/store_dimensions.cr` | Plugin: image width/height extraction (FastImage, Identify analyzers) |
| `src/gemma/plugins/column.cr` | Plugin: column serialization for database storage |
| `spec/` | Test files using Spectator framework |

## Architecture Overview

**Core components:**

1. **Gemma** (base class) — Central uploader with Habitat configuration, plugin system via `load_plugin`/`finalize_plugins!` macros, file upload/metadata extraction pipeline
2. **UploadedFile** — JSON-serializable representation of an uploaded file. Stores id, storage_key, and metadata hash. Provides url, exists?, open, download, stream, delete, replace methods
3. **Attacher** — Manages the attachment lifecycle: caching (temporary), promoting (cache to store), dirty tracking, finalization (cleanup + promote), destruction
4. **Storage adapters** — Pluggable backends implementing abstract Base class (FileSystem, Memory, S3)
5. **Grant integration** — `Attachable` module providing has_one_attached/has_many_attached macros that generate setter/getter/url/changed? methods plus before_save/after_save/after_destroy callbacks
6. **Validators** — `AttachmentValidators` module with compile-time macros for declarative validation
7. **Plugins** — Module-based extension system injecting ClassMethods, InstanceMethods, FileMethods, etc.

## Development Workflow

1. Run `shards install` after cloning or updating dependencies
2. Make changes to source files in `src/gemma/`
3. Run `crystal spec` to verify all tests pass
4. Run `./bin/ameba` to check code quality
5. Run `crystal tool format` to ensure consistent formatting

**Testing notes:**
- Tests use Spectator framework
- Use `Gemma::Storage::Memory` in tests for speed and isolation
- Call `clear!` on Memory storage between tests to reset state
- Some Grant tests require SQLite; mock-based tests are used as alternative

## Key Implementation Details

**Storage configuration (required before any uploads):**
```crystal
Gemma.configure do |config|
  config.storages["cache"] = Gemma::Storage::FileSystem.new("uploads", prefix: "cache")
  config.storages["store"] = Gemma::Storage::FileSystem.new("uploads")
end
```

**JSON column naming convention:** Attachment columns must be named `<attachment_name>_data` with type `JSON::Any?`:
```crystal
column avatar_data : JSON::Any?       # for has_one_attached :avatar
column documents_data : JSON::Any?    # for has_many_attached :documents
```

**Grant model integration:**
```crystal
class User < Grant::Base
  include Gemma::Grant::Attachable

  column id : Int64, primary: true
  column avatar_data : JSON::Any?

  has_one_attached :avatar
end
```

**Validation macros** (from `Gemma::Grant::AttachmentValidators`):
- `validate_file_size_of :name, maximum:, minimum:, message:` — byte size limits
- `validate_content_type_of :name, accept:, reject:, message:` — MIME type whitelist/blacklist with wildcard support
- `validate_presence_of :name, message:` — attachment must exist
- `validate_dimensions_of :name, width:, height:, message:` — image dimension ranges
- `validate_collection_size_of :name, maximum:, minimum:, message:` — count limits for has_many

**Plugin loading pattern:**
```crystal
class MyUploader < Gemma
  load_plugin(Gemma::Plugins::DetermineMimeType,
    analyzer: Gemma::Plugins::DetermineMimeType::Tools::File)
  finalize_plugins!    # MUST be called after all load_plugin calls
end
```

**MetadataType alias:** `Hash(String, String | Int16 | UInt16 | Int32 | UInt32 | Int64 | UInt64 | Nil)`

**has_many_attached singular derivation:** Strips trailing "s" from the name. `:documents` generates `add_document`, `remove_document`, `clear_documents`.

## Common Tasks

**Add a new storage adapter:** Create a file in `src/gemma/storage/`, inherit from `Gemma::Storage::Base`, implement abstract methods: `upload`, `open`, `exists?`, `delete`, `url`, `clean`. Add tests in `spec/gemma/storage/`.

**Create a new plugin:** Define a module under `Gemma::Plugins` with sub-modules for the injection points you need (ClassMethods, InstanceMethods, FileMethods, etc.). Optionally define `DEFAULT_OPTIONS` constant.

**Debugging tips:**
- Use `Log.debug { "message" }` (project uses Crystal's Log module)
- Inspect metadata: `pp uploaded_file.metadata`
- Memory storage is useful for debugging without filesystem side effects
- Check `uploaded_file.storage_key` to verify cache vs store placement

## Known Issues

1. Directory cleanup test (line 170-177 in `spec/gemma/storage/file_system_spec.cr`) is pending due to architectural issues
2. Some Grant tests require SQLite which may not be available on all systems
3. Crystal version requirement: >= 1.0.0, < 2.0.0
