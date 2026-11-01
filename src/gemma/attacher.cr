module Gemma
  # Core class that handles attaching files. It uses Gemma and
  # Gemma::UploadedFile objects internally.
  class Attacher
    # The uploader this attacher uploads with. Each uploader subclass has
    # its own `Attacher` subclass that returns it.
    def self.uploader_class : Gemma::Uploader.class
      Gemma::Uploader
    end

    module ClassMethods
      # Initializes the attacher from a data hash generated from `Attacher#data`.
      #
      # ```
      # attacher = Attacher.from_data(uploaded_file)
      # attacher.file # => #<Gemma::UploadedFile>
      # ```
      def from_data(data : UploadedFile?, **options)
        attacher = new(**options)
        attacher.load_data(data)
        attacher
      end

      # Initializes the attacher from a database column's JSON (trusted: it
      # is what Gemma wrote), or nil for an empty column.
      #
      # ```
      # Attacher.from_column(%({"id":"...","storage_key":"store","metadata":{}}))
      # ```
      def from_column(data : String?, **options)
        attacher = new(**options)
        attacher.load_column(data)
        attacher
      end
    end

    module InstanceMethods
      # Returns the attached uploaded file.
      property file : Gemma::UploadedFile?

      # Returns options that are automatically forwarded to the uploader.
      # Can be modified with additional data.
      getter :context

      getter :cache_key
      getter :store_key

      @previous : Gemma::Attacher?

      # Initializes the attached file, temporary and permanent storage.
      def initialize(@file : Gemma::UploadedFile? = nil, @cache_key : String = "cache", @store_key : String = "store")
        @file = file
        @cache_key = cache_key
        @store_key = store_key
        @context = Hash(String, String).new
      end

      # Calls #attach_cached, but skips if value is an empty string (this is
      # useful when the uploaded file comes from form fields). Forwards any
      # additional options to #attach_cached.
      #
      #     attacher.assign(File.open(...))
      #     attacher.assign(File.open(...), metadata: { "foo" => "bar" })
      #
      #     # ignores the assignment when a blank string is given
      #     attacher.assign("")
      def assign(value : IO?, **options)
        # return if value == "" # skip empty hidden field

        attach_cached(value, **options)
      end

      # Sets an existing cached file, or uploads an IO object to temporary
      # storage and sets it via #attach. Forwards any additional options to
      # #attach.
      #
      #     # upload file to temporary storage and set the uploaded file.
      #     attacher.attach_cached(File.open(...))
      #
      #     # foward additional options to the uploader
      #     attacher.attach_cached(File.open(...), metadata: { "foo" => "bar" })
      #
      #     # sets an existing cached file from JSON data
      #     attacher.attach_cached("{\"id\":\"...\",\"storage\":\"cache\",\"metadata\ ":{...}}")
      #
      #     # sets an existing cached file from Hash data
      #     attacher.attach_cached({ "id" => "...", "storage" => "cache", "metadata" => {} })
      def attach_cached(value : IO?, **options)
        attach(value, cache_key, **options)
      end

      # Caches a multipart part (anything shaped like `Amber::Router::File`).
      def attach_cached(part, **options)
        attach(part, cache_key, **options)
      end

      # An `UploadedFile` can be deserialized from client JSON, so it goes
      # through the same checks as a reference: it must be a file the cache
      # holds, and its metadata is read again from the stored bytes.
      def attach_cached(value : UploadedFile, **options)
        reference = CachedFileReference.new(value.id, value.storage_key, CachedFileReference::ClientMetadata.new(value.original_filename))
        change(cached(reference))
      end

      # Attaches the cached file a client's reference names, after checking
      # that the cache issued it (see `#cached`).
      def attach_cached(reference : CachedFileReference, **options)
        change(cached(reference))
      end

      def attach_cached(value : String | Hash(String, String), **options)
        change(cached(CachedFileReference.parse(value.is_a?(String) ? value : value.to_json)))
      end

      # Uploads given IO object and changes the uploaded file.
      #
      #     # uploads the file to permanent storage
      #     attacher.attach(io)
      #
      #     # uploads the file to specified storage
      #     attacher.attach(io, storage: :other_store)
      #
      #     # forwards additional options to the uploader
      #     attacher.attach(io, upload_options: { "x-amz-acl": "public-read" }, metadata: { "foo" => "bar" })
      #
      #     # removes the attachment
      #     attacher.attach(nil)
      def attach(io : IO | Gemma::UploadedFile?, storage = store_key, **options) : UploadedFile?
        file = upload(io, storage, **options) if io

        change(file)
      end

      # Uploads a multipart part (anything shaped like
      # `Amber::Router::File`) and changes the uploaded file.
      def attach(part, storage = store_key, **options) : UploadedFile?
        change(upload(part, storage, **options))
      end

      # Deletes any previous file, promotes a newly attached cached file, and
      # clears dirty tracking.
      #
      # This was called `finalize` before Gemma 0.7. Crystal calls a method
      # named `finalize` from the garbage collector, so every abandoned
      # attacher (a form that failed validation, say) was promoted to
      # permanent storage on the GC thread.
      #
      # ```
      # attacher.assign(io)
      # attacher.cached? # => true
      # attacher.promote_and_cleanup
      # attacher.stored?  # => true
      # attacher.changed? # => false
      # ```
      def promote_and_cleanup : Nil
        destroy_previous
        promote_cached
        @previous = nil if changed?
      end

      # If a new cached file has been attached, uploads it to permanent storage.
      # Any additional options are forwarded to #promote.
      #
      #     attacher.assign(io)
      #     attacher.cached? #=> true
      #     attacher.promote_cached
      #     attacher.stored? #=> true
      def promote_cached(**options)
        promote(**options) if promote?
      end

      # Uploads current file to permanent storage and sets the stored file.
      #
      #     attacher.cached? #=> true
      #     attacher.promote
      #     attacher.stored? #=> true
      def promote(storage = store_key, **options) : Gemma::UploadedFile?
        if attached_file = file
          set upload(attached_file, storage, **options)
        end
      end

      # Delegates to `Gemma.upload`, passing the #context.
      #
      #     # upload file to specified storage
      #     attacher.upload(io, "store") #=> #<Gemma::UploadedFile>
      #
      #     # pass additional options for the uploader
      #     attacher.upload(io, "store", metadata: { "foo" => "bar" })
      def upload(io, storage = store_key, **options) : Gemma::UploadedFile
        uploader_class.upload(io, storage, **options)
      end

      # If a new file was attached, deletes previously attached file if any.
      #
      #     previous_file = attacher.file
      #     attacher.attach(file)
      #     attacher.destroy_previous
      #     previous_file.exists? #=> false
      def destroy_previous
        @previous.try(&.destroy_attached)
      end

      # Destroys the attached file if it exists and is uploaded to permanent
      # storage.
      #
      #     attacher.file.exists? #=> true
      #     attacher.destroy_attached
      #     attacher.file.exists? #=> false
      def destroy_attached
        destroy if destroy?
      end

      # Destroys the attachment.
      #
      #     attacher.file.exists? #=> true
      #     attacher.destroy
      #     attacher.file.exists? #=> false
      def destroy
        file.try &.delete
      end

      # Returns attached file or raises an exception if no file is attached.
      def file! : Gemma::UploadedFile
        file || raise NoFileAttached.new("no file is attached")
      end

      # Loads a file Gemma stored earlier (from `Attacher#data`, or a
      # database column), without dirty tracking. The data is trusted, so
      # never pass it a client's input; use `#attach_cached` for that.
      #
      # ```
      # attacher.load_data(uploaded_file)
      # attacher.file # => #<Gemma::UploadedFile>
      # ```
      def load_data(data : UploadedFile?) : UploadedFile?
        @file = data
      end

      # Sets the uploaded file with dirty tracking, and runs validations.
      #
      #     attacher.change(uploaded_file)
      #     attacher.file #=> #<Gemma::UploadedFile>
      #     attacher.changed? #=> true
      def change(file : Gemma::UploadedFile?) : Gemma::UploadedFile?
        @previous = dup unless @file == file

        set(file)
      end

      # Sets the uploaded file.
      #
      #     attacher.set(uploaded_file)
      #     attacher.file #=> #<Gemma::UploadedFile>
      #     attacher.changed? #=> false
      def set(file : Gemma::UploadedFile?) : Gemma::UploadedFile?
        @file = file
      end

      # Returns the attached file.
      #
      #     # when a file is attached
      #     attacher.get #=> #<Gemma::UploadedFile>
      #
      #     # when no file is attached
      #     attacher.get #=> nil
      def get
        file
      end

      # If a file is attached, returns the uploaded file URL, otherwise returns
      # nil. Any options are forwarded to the storage.
      #
      #     attacher.file = file
      #     attacher.url #=> "https://..."
      #
      #     attacher.file = nil
      #     attacher.url #=> nil
      def url(**options)
        file.try &.url(**options)
      end

      # Returns whether the attachment has changed.
      #
      #     attacher.changed? #=> false
      #     attacher.attach(file)
      #     attacher.changed? #=> true
      #
      # TODO: This will work incorrect if `@previous` is nil
      def changed?
        !!@previous
      end

      # Returns whether a file is attached.
      #
      #     attacher.attach(io)
      #     attacher.attached? #=> true
      #
      #     attacher.attach(nil)
      #     attacher.attached? #=> false
      def attached?
        !!file
      end

      # Returns whether the file is uploaded to temporary storage.
      #
      #     attacher.cached?       # checks current file
      #     attacher.cached?(file) # checks given file
      def cached?(file = self.file)
        uploaded?(file, cache_key)
      end

      # Returns whether the file is uploaded to permanent storage.
      #
      #     attacher.stored?       # checks current file
      #     attacher.stored?(file) # checks given file
      def stored?(file = self.file)
        uploaded?(file, store_key)
      end

      # The attached file, for storing (its JSON is what a column holds).
      #
      # ```
      # attacher.data.to_json # => %({"id":"...","storage_key":"store","metadata":{...}})
      # ```
      def data : UploadedFile?
        file
      end

      # Loads the attachment from a database column's JSON.
      def load_column(data : String) : UploadedFile?
        load_data(UploadedFile.from_json(data))
      end

      def load_column(data : Nil) : Nil
        load_data(nil)
        nil
      end

      # The attached file as JSON for a database column, or nil when
      # nothing is attached.
      def column_data : String?
        file.try &.to_json
      end

      # The uploader this attacher uploads with.
      def uploader_class : Gemma::Uploader.class
        self.class.uploader_class
      end

      # Turns a client's cached-file reference into an `UploadedFile`, after
      # checking that the cache issued it: the storage key must be this
      # attacher's cache, the id must have the shape of a generated location,
      # and the file must exist in the cache. Size and MIME type are read
      # from the stored bytes; only the original filename comes from the
      # client. Raises `Gemma::NotCached` or `Gemma::InvalidLocation`.
      private def cached(reference : CachedFileReference) : UploadedFile
        # Files outside the cache would let one user claim another user's
        # stored attachment.
        unless reference.storage_key == cache_key
          raise NotCached.new("expected a file in the #{cache_key.inspect} storage, got #{reference.storage_key.inspect}")
        end

        unless CachedFileReference.valid_id?(reference.id)
          raise InvalidLocation.new("#{reference.id.inspect} is not a location Gemma generates")
        end

        cache_uploader = uploader_class.new(cache_key)
        unless cache_uploader.storage.exists?(reference.id)
          raise NotCached.new("no cached file #{reference.id.inspect}")
        end

        metadata = cache_uploader.extract_stored_metadata(reference.id, filename: reference.metadata.filename)
        UploadedFile.new(reference.id, cache_key, metadata)
      end

      # Whether attached file should be uploaded to permanent storage.
      private def promote?
        changed? && cached?
      end

      # Whether attached file should be deleted.
      private def destroy?
        attached? && !cached?
      end

      # Returns whether the file is uploaded to specified storage.
      private def uploaded?(file, storage_key)
        file.try &.storage_key == storage_key
      end
    end

    extend ClassMethods
    include InstanceMethods
  end
end
