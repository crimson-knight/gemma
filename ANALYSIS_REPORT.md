# Gemma Test Analysis and Grant Integration Plan

## Part 1: Commented Out Tests Analysis

### Found Commented Tests

1. **File: `spec/gemma/storage/file_system_spec.cr`**
   - Line 170-177: Test for "cleans moved file's directory"
   - **Issue**: The test is attempting to test file movement cleanup functionality
   - **Recommendation**: Can be re-enabled after fixing the `location` parameter issue
   - **Fix needed**: Update the upload method call to use proper named parameters

2. **File: `spec/gemma/uploaded_file_spec.cr`**
   - Lines 68-71: Test for extension extraction from ID
   - Lines 80-83: Test for extension extraction from metadata filename
   - **Issue**: Both tests cause "Invalid memory access (signal 11) at address 0x0" 
   - **Root Cause**: Likely a null pointer dereference in the extension extraction logic
   - **Recommendation**: Debug the extension extraction method to handle edge cases properly

### Test Re-enablement Action Items

1. **File System Test (line 170-177)**:
   ```crystal
   # Current (broken):
   uploaded_file = subject.upload(fakeio, location: "a/a/a.jpg")
   
   # Fixed:
   uploaded_file = subject.upload(fakeio, "a/a/a.jpg")
   ```

2. **Extension Tests**: Need to investigate the segfault in the `#extension` method when processing filenames with extensions.

## Part 2: Grant ORM Integration Plan

### Architecture Design

#### Core Module Structure

```crystal
# src/gemma/grant.cr
module Gemma
  module Grant
    module Attachable
      # This module will be included in Grant models
      macro included
        macro has_one_attached(name, uploader = nil)
          # Implementation here
        end
        
        macro has_many_attached(name, uploader = nil)
          # Implementation here
        end
      end
    end
  end
end
```

### Implementation Strategy

#### Phase 1: Core Attachment Module
1. Create `src/gemma/grant/attachable.cr` with base macros
2. Implement `has_one_attached` macro that:
   - Creates a getter/setter for single file attachment
   - Handles JSON serialization/deserialization
   - Integrates with Grant's callbacks (before_save, after_save)
   
3. Implement `has_many_attached` macro that:
   - Creates array-based attachment management
   - Handles multiple file uploads
   - Provides collection methods (add, remove, clear)

#### Phase 2: Grant Model Integration
```crystal
class Document < Grant::Model
  include Gemma::Grant::Attachable
  
  # Single attachment
  has_one_attached :avatar, uploader: AvatarUploader
  
  # Multiple attachments
  has_many_attached :images, uploader: ImageUploader
end
```

#### Phase 3: Database Schema Support
- Store attachment data as JSON in database columns
- Column naming convention: `{name}_data` for has_one_attached
- Column naming convention: `{name}_data` with JSON array for has_many_attached

### Key Features to Implement

1. **Automatic Caching**: Files uploaded through forms are cached temporarily
2. **Promotion on Save**: Move files from cache to permanent storage after successful save
3. **Background Processing Support**: Allow async file processing
4. **Deletion Handling**: Clean up files when records are destroyed
5. **Validation Support**: Integrate with Grant's validation system

### Migration Helper
```crystal
# Create a migration helper for Grant
class AddAttachmentsToDocuments < Grant::Migration
  def up
    alter_table :documents do
      add_column :avatar_data, :json
      add_column :images_data, :json
    end
  end
end
```

### Example Usage
```crystal
# Upload single file
document = Document.new
document.avatar = params.files["avatar"] # HTTP::FormData::Part
document.save

# Access attachment
document.avatar.url
document.avatar.metadata

# Upload multiple files
document.images = params.files.select("images[]")
document.save

# Access multiple attachments
document.images.each do |image|
  puts image.url
end
```

## Part 3: Implementation Roadmap

### Step 1: Fix Existing Tests (Priority: High)
- [ ] Fix file_system_spec.cr line 170-177
- [ ] Debug and fix segfault in uploaded_file_spec.cr extension tests

### Step 2: Create Grant Integration Module (Priority: High)
- [ ] Create `src/gemma/grant/` directory structure
- [ ] Implement `Attachable` module with macros
- [ ] Add single attachment support (`has_one_attached`)
- [ ] Add multiple attachment support (`has_many_attached`)

### Step 3: Add Grant-specific Features (Priority: Medium)
- [ ] Callback integration (before_save, after_save, after_destroy)
- [ ] Validation helpers
- [ ] Migration generators

### Step 4: Testing & Documentation (Priority: Medium)
- [ ] Create comprehensive test suite for Grant integration
- [ ] Write usage documentation
- [ ] Add example application

### Step 5: Advanced Features (Priority: Low)
- [ ] Direct upload support
- [ ] Variants/derivatives for images
- [ ] Background job integration

## Technical Considerations

1. **Memory Management**: Crystal's memory management differs from Ruby; ensure proper cleanup
2. **Type Safety**: Leverage Crystal's type system for compile-time guarantees
3. **Performance**: Consider lazy loading for attachment metadata
4. **Compatibility**: Ensure compatibility with Grant's query interface

## Next Immediate Actions

1. Fix the commented tests to ensure core functionality works
2. Create basic Grant integration module structure
3. Implement minimal viable `has_one_attached` macro
4. Test with a simple Grant model
5. Iterate and expand functionality