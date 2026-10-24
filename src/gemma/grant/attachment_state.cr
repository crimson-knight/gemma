module Gemma
  module Grant
    # What one save wrote for one attachment: the column value, the files it
    # promoted and their cached copies. Kept until the transaction settles.
    class SaveEntry(T)
      getter written : T
      getter column_before : T
      getter list_of_promotions : Array({Gemma::Attacher, Gemma::UploadedFile, Gemma::UploadedFile})
      property? undone = false

      def initialize(@written : T, @column_before : T, @list_of_promotions)
      end

      def promoted_files : Array(Gemma::UploadedFile)
        list_of_promotions.map { |_attacher, _cached, promoted| promoted }
      end

      def cached_files : Array(Gemma::UploadedFile)
        list_of_promotions.map { |_attacher, cached, _promoted| cached }
      end
    end

    # The attachment state of one record between commits, shared by
    # `has_one_attached` (`T` is `Gemma::UploadedFile?`) and
    # `has_many_attached` (`T` is `Array(Gemma::UploadedFile)`).
    #
    # Assigning only caches. Each save promotes the cached files it finds
    # and records a `SaveEntry`; Gemma registers an undo for that entry with
    # the transaction, so a rollback (of the whole transaction, or of only
    # the savepoint that held the save) deletes exactly the files that save
    # promoted. When the transaction commits, the files the last save
    # replaced or removed, files earlier saves promoted and the last one
    # replaced, and every cached copy are deleted. Nothing is deleted before
    # a commit.
    abstract class AttachmentState(T)
      # The column value the committed row holds.
      getter committed : T
      @ledger = [] of SaveEntry(T)
      @changed = false

      def initialize(@committed : T)
      end

      # Whether there are assignments no save has written yet.
      def changed? : Bool
        @changed
      end

      # The column value Gemma expects the record to hold: what the last
      # save wrote, or what the committed row holds. A different value was
      # set on the column directly, bypassing the checks assignment makes.
      def expected_column : T
        if entry = @ledger.reverse.find { |candidate| !candidate.undone? }
          entry.written
        else
          committed
        end
      end

      abstract def current_value : T
      abstract def cached_attachers : Array(Gemma::Attacher)

      # Promotes every cached file and records the save. Returns the entry,
      # whose undo the caller registers with the transaction.
      def prepare_save(column_before : T) : SaveEntry(T)
        promotions = cached_attachers.compact_map do |attacher|
          cached = attacher.file
          promoted = attacher.promote
          {attacher, cached, promoted} if cached && promoted
        end
        entry = SaveEntry(T).new(current_value, column_before, promotions)
        @ledger << entry
        @changed = false
        entry
      end

      # Undoes one save: deletes the files it promoted and points their
      # attachers back at the cached copies, so a later save promotes them
      # again. Returns the column value from before that save. Safe to call
      # twice.
      def undo(entry : SaveEntry(T)) : T
        unless entry.undone?
          entry.undone = true
          entry.list_of_promotions.each do |attacher, cached, promoted|
            promoted.delete
            attacher.set(cached) if attacher.file == promoted
          end
          @changed = true unless entry.list_of_promotions.empty?
        end
        entry.column_before
      end

      # After the transaction commits a save: deletes what the final row no
      # longer names, every file an earlier save promoted that the final
      # one replaced, and the cached copies.
      def commit_save : Nil
        live = @ledger.reject(&.undone?)
        @ledger.clear
        return if live.empty?

        final = live.last.written
        kept = files_of(final)
        doomed = files_of(committed) + live.flat_map(&.promoted_files)
        doomed.uniq.each { |stored| stored.delete unless kept.includes?(stored) }
        live.flat_map(&.cached_files).uniq!.each(&.delete)
        @committed = final
      end

      # After the record's destroy commits: deletes every stored file the
      # record held or any save in the transaction promoted, and the cached
      # copies those saves made.
      def commit_destroy : Nil
        live = @ledger.reject(&.undone?)
        @ledger.clear
        stored = files_of(committed) + live.flat_map(&.promoted_files) + files_of(current_value).reject { |file| cached?(file) }
        stored.uniq.each(&.delete)
        live.flat_map(&.cached_files).uniq!.each(&.delete)
      end

      abstract def files_of(value : T) : Array(Gemma::UploadedFile)
      abstract def cached?(file : Gemma::UploadedFile) : Bool
    end

    # One `has_one_attached` attachment of one record.
    class SingleAttachment < AttachmentState(Gemma::UploadedFile?)
      getter attacher : Gemma::Attacher

      def initialize(@attacher : Gemma::Attacher, committed : Gemma::UploadedFile?)
        super(committed)
        @attacher.load_data(committed)
      end

      def file : Gemma::UploadedFile?
        attacher.file
      end

      # Caches an upload: an `IO`, or a multipart part such as
      # `Amber::Router::File`.
      def assign(io : IO) : Nil
        attacher.attach_cached(io)
        @changed = true
      end

      # Attaches the cached file a client's reference names, after the
      # attacher has checked it.
      def assign(reference : Gemma::CachedFileReference) : Nil
        attacher.attach_cached(reference)
        @changed = true
      end

      # Removes the attachment; the stored file is deleted after commit.
      def assign(value : Nil) : Nil
        attacher.attach(nil)
        @changed = true
      end

      def assign(part) : Nil
        attacher.attach_cached(part)
        @changed = true
      end

      def current_value : Gemma::UploadedFile?
        attacher.file
      end

      def cached_attachers : Array(Gemma::Attacher)
        attacher.cached? ? [attacher] : [] of Gemma::Attacher
      end

      def files_of(value : Gemma::UploadedFile?) : Array(Gemma::UploadedFile)
        value ? [value] : [] of Gemma::UploadedFile
      end

      def cached?(file : Gemma::UploadedFile) : Bool
        attacher.cached?(file)
      end
    end

    # The `has_many_attached` list of one record.
    class AttachmentList < AttachmentState(Array(Gemma::UploadedFile))
      getter list_of_attachers : Array(Gemma::Attacher)

      def initialize(@attacher_factory : Proc(Gemma::Attacher), committed : Array(Gemma::UploadedFile)?)
        super(committed || [] of Gemma::UploadedFile)
        @list_of_attachers = @committed.map do |stored|
          attacher = @attacher_factory.call
          attacher.load_data(stored)
          attacher
        end
      end

      def files : Array(Gemma::UploadedFile)
        list_of_attachers.compact_map(&.file)
      end

      # Replaces the whole list. Every value is cached first; if one fails,
      # the list is unchanged and the files cached for it are deleted.
      def replace(values : Array) : Nil
        replacements = [] of Gemma::Attacher
        begin
          values.each { |value| replacements << build(value) }
        rescue error
          replacements.each(&.file.try(&.delete))
          raise error
        end
        @list_of_attachers = replacements
        @changed = true
      end

      def add(value) : Nil
        list_of_attachers << build(value)
        @changed = true
      end

      # Removes *file* from the list; it is deleted after commit.
      def remove(file : Gemma::UploadedFile) : Nil
        list_of_attachers.reject! { |attacher| attacher.file == file }
        @changed = true
      end

      # Removes every file; they are deleted after commit.
      def clear : Nil
        list_of_attachers.clear
        @changed = true
      end

      def current_value : Array(Gemma::UploadedFile)
        files
      end

      def cached_attachers : Array(Gemma::Attacher)
        list_of_attachers.select(&.cached?)
      end

      def files_of(value : Array(Gemma::UploadedFile)) : Array(Gemma::UploadedFile)
        value
      end

      def cached?(file : Gemma::UploadedFile) : Bool
        list_of_attachers.any? { |attacher| attacher.file == file && attacher.cached? }
      end

      private def build(value) : Gemma::Attacher
        attacher = @attacher_factory.call
        attacher.attach_cached(value)
        attacher
      end
    end
  end
end
