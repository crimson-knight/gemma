---
name: gemma-setup-attachments
description: Set up Gemma file attachments in a Grant model — configures storage, adds attachment columns, and integrates with an existing or new model.
allowed-tools: Bash, Read, Write, Edit, Glob
user-invocable: true
argument-hint: <ModelName> <attachment_name> [--storage=filesystem|s3] [--multiple] [--with-validations]
---

# Set Up Gemma File Attachments

This skill walks through the complete process of adding Gemma file attachments to a Grant ORM model in an Amber application. It handles dependency checking, storage configuration, model modification, and optional validation setup.

## Procedure

Follow these steps in order. Read the current state of the project before making changes.

### Step 1: Check shard.yml for Gemma Dependency

Read `shard.yml` and verify that Gemma is listed as a dependency:

```yaml
dependencies:
  gemma:
    github: crimson-knight/gemma
```

If Gemma is not present, add it to the `dependencies` section and run `shards install`.

Also verify that Grant is listed:

```yaml
dependencies:
  grant:
    github: crimson-knight/grant
    branch: main
```

### Step 2: Check for Existing Storage Configuration

Search the project for an existing Gemma storage configuration. Look for:

```crystal
Gemma.configure do |config|
```

Common locations to check:
- `config/initializers/gemma.cr`
- `config/initializers/storage.cr`
- `config/initializers/*.cr`
- `src/config/*.cr`
- The main application entry point

If a storage configuration already exists, note its location and what storages are configured. Do not duplicate it.

### Step 3: Create Storage Configuration (if needed)

If no storage configuration exists, create one. The location depends on the project structure:

- **Amber app**: Create `config/initializers/gemma.cr`
- **Standalone app**: Create in the appropriate config directory or main entry point

**For filesystem storage (default):**

```crystal
require "gemma"

Gemma.configure do |config|
  config.storages["cache"] = Gemma::Storage::FileSystem.new("uploads", prefix: "cache")
  config.storages["store"] = Gemma::Storage::FileSystem.new("uploads")
end
```

**For S3 storage:**

```crystal
require "gemma"
require "awscr-s3"

client = Awscr::S3::Client.new(
  ENV["AWS_REGION"],
  ENV["AWS_ACCESS_KEY_ID"],
  ENV["AWS_SECRET_ACCESS_KEY"]
)

Gemma.configure do |config|
  config.storages["cache"] = Gemma::Storage::S3.new(
    bucket: ENV["S3_BUCKET"],
    client: client,
    prefix: "cache"
  )
  config.storages["store"] = Gemma::Storage::S3.new(
    bucket: ENV["S3_BUCKET"],
    client: client,
    prefix: "store",
    public: true
  )
end
```

Also check that the main application requires the Grant integration:

```crystal
require "gemma/grant"
```

If this require is missing, add it near the storage configuration or in the model file.

### Step 4: Find or Create the Grant Model

Search for the target model file. Common patterns:
- `src/models/<model_name>.cr`
- `src/app/models/<model_name>.cr`

If the model file does not exist, confirm with the user before creating a new model.

### Step 5: Add the Attachable Include

Check if the model already includes `Gemma::Grant::Attachable`. If not, add it after the class declaration:

```crystal
class <ModelName> < Grant::Base
  include Gemma::Grant::Attachable
```

If `--with-validations` is specified, also add:

```crystal
  include Gemma::Grant::AttachmentValidators
```

### Step 6: Add the JSON Column

The model needs a JSON column following the naming convention `<attachment_name>_data`:

Check if the column already exists in the model. If not, add it:

**For single attachments:**
```crystal
  column <attachment_name>_data : JSON::Any?
```

**For multiple attachments (--multiple):**
```crystal
  column <attachment_name>_data : JSON::Any?
```

The column type is the same for both single and multiple attachments. The difference is in the macro used.

### Step 7: Add the Attachment Macro

**For single attachments (default):**
```crystal
  has_one_attached :<attachment_name>
```

**For multiple attachments (--multiple):**
```crystal
  has_many_attached :<attachment_name>
```

Place the macro after all column definitions.

### Step 8: Add Validations (if --with-validations)

If the user requested validations, add appropriate validators after the attachment macro. Choose validators based on the attachment type:

**For image attachments:**
```crystal
  validate_file_size_of :<attachment_name>, maximum: 5_000_000
  validate_content_type_of :<attachment_name>, accept: ["image/jpeg", "image/png", "image/webp", "image/gif"]
```

**For document attachments:**
```crystal
  validate_file_size_of :<attachment_name>, maximum: 10_000_000
  validate_content_type_of :<attachment_name>, accept: [
    "application/pdf",
    "application/msword",
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
  ]
```

**For multiple attachments, also add:**
```crystal
  validate_collection_size_of :<attachment_name>, maximum: 10
```

Ask the user about specific size limits and content types if they are not specified.

### Step 9: Remind About Database Migration

After modifying the model, remind the user that the database table needs a corresponding JSON column:

**PostgreSQL:**
```sql
ALTER TABLE <table_name> ADD COLUMN <attachment_name>_data JSONB;
```

**MySQL:**
```sql
ALTER TABLE <table_name> ADD COLUMN <attachment_name>_data JSON;
```

**SQLite:**
```sql
ALTER TABLE <table_name> ADD COLUMN <attachment_name>_data TEXT;
```

### Step 10: Verify the Setup

Run the Crystal compiler to check for errors:

```bash
crystal build src/<main_file>.cr --no-codegen
```

Or run the test suite:

```bash
crystal spec
```

## Example: Complete Walkthrough

Given the command: `User avatar --storage=filesystem --with-validations`

The resulting model should look like:

```crystal
require "gemma/grant"

class User < Grant::Base
  include Gemma::Grant::Attachable
  include Gemma::Grant::AttachmentValidators

  self.connection_name = "primary"
  self.table_name = "users"

  column id : Int64, primary: true
  column email : String
  column name : String?
  column avatar_data : JSON::Any?
  column created_at : Time?
  column updated_at : Time?

  has_one_attached :avatar

  validate_file_size_of :avatar, maximum: 5_000_000
  validate_content_type_of :avatar, accept: ["image/jpeg", "image/png", "image/webp"]
end
```

## Example: Multiple Attachments

Given the command: `Product images --multiple --with-validations`

```crystal
require "gemma/grant"

class Product < Grant::Base
  include Gemma::Grant::Attachable
  include Gemma::Grant::AttachmentValidators

  self.connection_name = "primary"
  self.table_name = "products"

  column id : Int64, primary: true
  column name : String
  column images_data : JSON::Any?

  has_many_attached :images

  validate_file_size_of :images, maximum: 10_000_000
  validate_content_type_of :images, accept: ["image/*"]
  validate_collection_size_of :images, maximum: 20
end
```

## Checklist

After completing the setup, verify:

- [ ] Gemma is in `shard.yml` and `shards install` has been run
- [ ] `require "gemma/grant"` is present in the require chain
- [ ] Gemma storage is configured with at least "cache" and "store"
- [ ] Model includes `Gemma::Grant::Attachable`
- [ ] Model has a `<name>_data : JSON::Any?` column
- [ ] Attachment macro (`has_one_attached` or `has_many_attached`) is declared
- [ ] Database table has the corresponding JSON/JSONB/TEXT column
- [ ] Validations are in place if requested (model also includes `AttachmentValidators`)
- [ ] Code compiles without errors
