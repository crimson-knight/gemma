module Gemma
  module Grant
    # One `has_one_attached` attachment of one record, between saves.
    #
    # Assigning only caches the new file. `before_save` promotes it to the
    # store and the column is written in the same statement; the replaced
    # file and the cached copy are deleted once the save commits, and the
    # promoted file is deleted if the save rolls back. Nothing is deleted
    # before a commit.
    class SingleAttachment
      getter attacher : Gemma::Attacher

      @persisted : Gemma::UploadedFile?
      @cached : Gemma::UploadedFile?
      @promoted : Gemma::UploadedFile?
      @changed = false

      # *persisted* is the file the record's column holds.
      def initialize(@attacher : Gemma::Attacher, @persisted : Gemma::UploadedFile?)
        @attacher.load_data(@persisted)
      end

      def file : Gemma::UploadedFile?
        attacher.file
      end

      def changed? : Bool
        @changed
      end

      # Caches an upload (an `IO`, or a multipart part such as
      # `Amber::Router::File`) as the new file.
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

      # Removes the attachment; the stored file is deleted at commit.
      def assign(value : Nil) : Nil
        attacher.attach(nil)
        @changed = true
      end

      def assign(part) : Nil
        attacher.attach_cached(part)
        @changed = true
      end

      # Promotes a newly cached file and returns what the column holds.
      def prepare_save : Gemma::UploadedFile?
        if @changed && attacher.cached? && @promoted.nil?
          @cached = attacher.file
          @promoted = attacher.promote
        end
        attacher.file
      end

      # After the save commits: deletes the replaced file and the cached copy.
      def commit_save : Nil
        return unless @changed

        current = attacher.file
        if (replaced = @persisted) && replaced != current
          replaced.delete
        end
        @cached.try(&.delete)
        @persisted = current
        @cached = nil
        @promoted = nil
        @changed = false
      end

      # After a failed save: deletes the promoted file and goes back to the
      # cached one, so saving again promotes it again. Returns what the
      # column held before the save.
      def roll_back_save : Gemma::UploadedFile?
        if promoted = @promoted
          promoted.delete
          attacher.set(@cached)
          @promoted = nil
          @cached = nil
        end
        @persisted
      end

      # After the record's destroy commits: deletes its stored file.
      def commit_destroy : Nil
        stored_files = [attacher.file, @persisted].compact.uniq!
        stored_files.each { |stored| stored.delete unless attacher.cached?(stored) }
      end
    end

    # The `has_many_attached` list of one record, between saves, with the
    # same deferred promotion and deletion as `SingleAttachment`.
    class AttachmentList
      getter list_of_attachers : Array(Gemma::Attacher)

      @persisted : Array(Gemma::UploadedFile)
      # Each promotion this save made: the attacher, its cached file and the
      # stored copy.
      @promotions = [] of {Gemma::Attacher, Gemma::UploadedFile, Gemma::UploadedFile}
      @changed = false

      # *persisted* is the list the record's column holds.
      def initialize(@attacher_factory : -> Gemma::Attacher, persisted : Array(Gemma::UploadedFile)?)
        @persisted = persisted || [] of Gemma::UploadedFile
        @list_of_attachers = @persisted.map do |stored|
          attacher = @attacher_factory.call
          attacher.load_data(stored)
          attacher
        end
      end

      def files : Array(Gemma::UploadedFile)
        list_of_attachers.compact_map(&.file)
      end

      def changed? : Bool
        @changed
      end

      # Replaces the whole list with new uploads or cached references.
      def replace(values : Array) : Nil
        list_of_attachers.clear
        values.each { |value| add(value) }
        @changed = true
      end

      def add(value) : Nil
        attacher = @attacher_factory.call
        attacher.attach_cached(value)
        list_of_attachers << attacher
        @changed = true
      end

      # Removes *file* from the list; it is deleted at commit.
      def remove(file : Gemma::UploadedFile) : Nil
        list_of_attachers.reject! { |attacher| attacher.file == file }
        @changed = true
      end

      # Removes every file; they are deleted at commit.
      def clear : Nil
        list_of_attachers.clear
        @changed = true
      end

      def prepare_save : Array(Gemma::UploadedFile)
        if @changed
          list_of_attachers.each do |attacher|
            next unless attacher.cached?

            cached = attacher.file
            promoted = attacher.promote
            @promotions << {attacher, cached, promoted} if cached && promoted
          end
        end
        files
      end

      def commit_save : Nil
        return unless @changed

        current = files
        @persisted.each { |stored| stored.delete unless current.includes?(stored) }
        @promotions.each { |_attacher, cached, _promoted| cached.delete }
        @persisted = current
        @promotions.clear
        @changed = false
      end

      def roll_back_save : Array(Gemma::UploadedFile)
        @promotions.each do |attacher, cached, promoted|
          promoted.delete
          attacher.set(cached)
        end
        @promotions.clear
        @persisted
      end

      def commit_destroy : Nil
        stored_files = list_of_attachers.compact_map { |attacher| attacher.file unless attacher.cached? }
        (stored_files + @persisted).uniq.each(&.delete)
      end
    end
  end
end
