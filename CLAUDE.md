# Gemma Project Guide for Claude Code

## Project Overview

Gemma is a Crystal file attachment toolkit inspired by Ruby's Shrine gem. It provides a flexible and powerful system for handling file uploads, storage, and management in Crystal applications. This project is a fork from JetRockets' shrine.cr, now maintained to provide comprehensive file attachment capabilities for Crystal frameworks.

## Core Architecture

### Main Components

1. **Gemma Base Class** (`src/gemma.cr`)
   - Central uploader class with plugin system
   - Handles file upload, storage, and metadata extraction
   - Extensible through inheritance and plugins

2. **Storage Adapters** (`src/gemma/storage/`)
   - `FileSystem`: Local file storage
   - `Memory`: In-memory storage (mainly for testing)
   - `S3`: AWS S3 and compatible services (DigitalOcean Spaces, Minio)

3. **UploadedFile** (`src/gemma/uploaded_file.cr`)
   - Represents uploaded files with metadata
   - Provides methods for file operations (download, delete, url, etc.)
   - JSON serializable for database storage

4. **Attacher** (`src/gemma/attacher.cr`)
   - Manages file attachment lifecycle
   - Handles promotion from cache to permanent storage

5. **Grant ORM Integration** (`src/gemma/grant/`)
   - Complete ActiveStorage-like integration for Grant ORM
   - Provides `has_one_attached` and `has_many_attached` macros
   - Includes comprehensive validation system

## Build and Test Commands

```bash
# Install dependencies
shards install

# Run tests
crystal spec

# Run specific test file
crystal spec spec/gemma/grant/simple_attachable_spec.cr

# Run with verbose output
crystal spec --verbose

# Check code quality with Ameba linter
./bin/ameba

# Build for release (if creating a binary)
crystal build src/gemma.cr --release
```

## Development Workflow

### 1. Setting Up Development Environment

```bash
# Clone the repository
git clone https://github.com/crimson-knight/gemma.git
cd gemma

# Install dependencies
shards install

# Create a new branch for your work
git checkout -b feature/your-feature-name
```

### 2. Running Tests

The project uses Spectator testing framework. Tests are located in the `spec/` directory.

```bash
# Run all tests
crystal spec

# Run tests matching a pattern
crystal spec --example "UploadedFile"

# Run with seed for reproducible test order
crystal spec --seed 12345
```

### 3. Code Quality

The project uses Ameba for linting:

```bash
# Run linter
./bin/ameba

# Run on specific files
./bin/ameba src/gemma/grant/attachable.cr

# Generate config
./bin/ameba --gen-config
```

## Key Implementation Details

### Storage Configuration

```crystal
Gemma.configure do |config|
  # File system storage
  config.storages["cache"] = Gemma::Storage::FileSystem.new("uploads", prefix: "cache")
  config.storages["store"] = Gemma::Storage::FileSystem.new("uploads")
  
  # S3 storage
  client = Awscr::S3::Client.new("region", "key", "secret")
  config.storages["s3"] = Gemma::Storage::S3.new(
    bucket: "my-bucket",
    client: client,
    prefix: "uploads"
  )
end
```

### Custom Uploaders

Create custom uploaders by inheriting from `Gemma`:

```crystal
class ImageUploader < Gemma
  def generate_location(io, metadata, context, **options)
    name = super(io, metadata, **options)
    File.join("images", context[:model].id.to_s, name)
  end
end
```

### Grant ORM Integration

The Grant integration is fully implemented with these key features:

1. **Attachment Macros**: `has_one_attached` and `has_many_attached`
2. **Validation System**: File size, content type, dimensions, presence
3. **Automatic Cleanup**: Old files deleted when replaced
4. **JSON Storage**: Metadata stored in JSON columns

Example usage:
```crystal
class User < Grant::Base
  include Gemma::Grant::Attachable
  
  column avatar_data : JSON::Any?
  has_one_attached :avatar
end
```

## Common Tasks and Solutions

### Adding New Storage Adapter

1. Create new file in `src/gemma/storage/`
2. Inherit from `Gemma::Storage::Base`
3. Implement required methods: `upload`, `open`, `exists?`, `delete`, `url`
4. Add tests in `spec/gemma/storage/`

### Creating New Plugin

1. Create plugin module in `src/gemma/plugins/`
2. Define plugin modules: `ClassMethods`, `InstanceMethods`, `FileMethods`, etc.
3. Use `load_plugin` macro in uploader class
4. Add `finalize_plugins!` after loading all plugins

### Fixing Segmentation Faults

Common causes and solutions:
- **Nil handling**: Always use safe navigation (`?.`) or nil checks
- **Extension extraction**: Fixed in `src/gemma/uploaded_file.cr`
- **File operations**: Ensure files exist before operations

### Working with Crystal Macros

Crystal macros differ from Ruby metaprogramming:
- No named parameters in macros
- Use `{{name.id}}` for interpolation
- Escape with `\{{}}` when needed inside strings
- Be careful with nested macros

## Important Files and Their Purposes

- **src/gemma.cr**: Main Gemma class with core upload logic
- **src/gemma/uploaded_file.cr**: File representation and operations
- **src/gemma/storage/**: Storage adapter implementations
- **src/gemma/grant/attachable.cr**: Grant ORM integration macros
- **src/gemma/grant/validators.cr**: Validation helpers
- **spec/**: Test files using Spectator framework
- **examples/**: Usage examples for different scenarios
- **GRANT_COMPLETE_GUIDE.md**: Comprehensive Grant integration documentation

## Known Issues and Workarounds

1. **Directory cleanup test disabled**: Test at line 170-177 in `spec/gemma/storage/file_system_spec.cr` is pending due to architectural issues with directory removal

2. **SQLite dependency in tests**: Some Grant tests require SQLite which may not be available. Mock-based tests are used as alternative.

3. **Crystal version compatibility**: Requires Crystal >= 1.0.0, < 2.0.0

## Debugging Tips

1. **Use Log module**: The project uses Crystal's Log module
   ```crystal
   Log.debug { "Debug message" }
   Log.info { "Info message" }
   ```

2. **Test isolation**: Tests use `clear_storages` helper to reset state

3. **Metadata inspection**: Use `pp uploaded_file.metadata` to inspect file metadata

4. **Storage debugging**: Memory storage useful for testing without filesystem

## Integration with Web Frameworks

### Amber Framework
```crystal
def create
  file = params.files["avatar"]
  uploaded = Gemma.upload(file.file, "store", 
    metadata: { "filename" => file.filename })
end
```

### Lucky Framework
Similar pattern, adapt to Lucky's parameter handling.

## CI/CD Considerations

- Tests should pass on Crystal 1.0+ 
- Guardian.yml configured for continuous testing
- Ameba linting should pass (except known exclusions in .ameba.yml)

## Useful Chroma Memory Lookups

The Grant integration documentation has been stored in Chroma memory. To retrieve:

1. Basic usage: Search for "Grant ORM attachment usage"
2. Validations: Search for "Grant attachment validators"
3. Examples: Search for "Grant attachment examples"
4. Migration guides: Search for "Grant attachment migrations"

## Contributing Guidelines

1. Fork the repository
2. Create feature branch
3. Write tests for new features
4. Ensure all tests pass
5. Run Ameba linter
6. Submit pull request

## Support and Resources

- **GitHub Issues**: Report bugs and request features
- **Documentation**: README.md and GRANT_COMPLETE_GUIDE.md
- **Examples**: Check `examples/` directory for usage patterns
- **Tests**: Read test files for implementation examples

## Quick Reference

### Test a specific feature
```bash
crystal spec --example "has_one_attached"
```

### Check what's in uploads directory
```bash
ls -la uploads/
```

### Run Grant integration tests
```bash
crystal spec spec/gemma/grant/
```

### Verify examples compile
```bash
crystal build examples/grant_usage.cr
crystal build examples/grant_with_validations.cr
```

## Architecture Decisions

1. **Plugin System**: Allows extending functionality without modifying core
2. **Storage Abstraction**: Easy to add new storage backends
3. **Metadata System**: Flexible key-value storage for file information
4. **Grant Integration**: Seamless ORM integration with familiar Rails-like API

## Performance Considerations

- Use `move: true` when promoting files to avoid copying
- Memory storage is fastest for testing
- S3 storage supports direct uploads for large files
- File operations are IO-bound, consider background jobs for large uploads

## Security Best Practices

1. Always validate file types and sizes
2. Store files outside web root
3. Generate unique, unpredictable file names
4. Use signed URLs for private files
5. Implement rate limiting for uploads
6. Scan uploads for malware in production

Remember: Gemma is designed to be flexible and extensible. When in doubt, check the tests and examples for implementation patterns.