require "../attacher"
require "./attachment_converter"
require "./attachment_state"

module Gemma
  module Grant
    # Attachments on Grant models.
    #
    # ```
    # class User < Grant::Base
    #   include Gemma::Grant::Attachable
    #
    #   column id : Int64, primary: true
    #
    #   has_one_attached :avatar, uploader: AvatarUploader # declares avatar_data
    #   has_many_attached :documents                       # declares documents_data
    # end
    # ```
    #
    # Each macro declares its `<name>_data` column (TEXT, holding the file's
    # JSON), so the table needs that column and the model must not declare
    # it again. Assigning caches the upload; `save` promotes it to the store
    # in `before_save` and writes the column in the same statement. Replaced,
    # removed and cached files are deleted only after the save commits, and a
    # promoted file is deleted again if the save rolls back.
    module Attachable
      macro has_one_attached(name, uploader = Gemma::Uploader)
        {% state = "_#{name.id}_attachment".id %}
        {% column = "#{name.id}_data".id %}

        column {{ column }} : Gemma::UploadedFile?, converter: Gemma::Grant::AttachmentConverter, column_type: "TEXT"

        @[JSON::Field(ignore: true)]
        @[YAML::Field(ignore: true)]
        @{{ state }} : Gemma::Grant::SingleAttachment?

        private def {{ state }} : Gemma::Grant::SingleAttachment
          @{{ state }} ||= Gemma::Grant::SingleAttachment.new({{ uploader }}::Attacher.new, {{ column }})
        end

        # Caches *value* as the new {{ name.id }}: an `IO`, a multipart part
        # (`Amber::Router::File`), a `Gemma::CachedFileReference` from a
        # re-rendered form, or nil to remove it. Stored on `save`.
        def {{ name.id }}=(value) : Nil
          {{ state }}.assign(value)
        end

        def {{ name.id }} : Gemma::UploadedFile?
          {{ state }}.file
        end

        def {{ name.id }}_url(**options) : String?
          {{ name.id }}.try &.url(**options)
        end

        def {{ name.id }}_changed? : Bool
          {{ state }}.changed?
        end

        before_save :_prepare_{{ name.id }}_attachment
        around_save :_guard_{{ name.id }}_attachment
        after_save_commit :_commit_{{ name.id }}_attachment
        after_rollback :_roll_back_{{ name.id }}_attachment
        after_destroy_commit :_destroy_{{ name.id }}_attachment

        private def _prepare_{{ name.id }}_attachment : Nil
          return unless {{ state }}.changed?

          self.{{ column }} = {{ state }}.prepare_save
        end

        # Grant runs `after_rollback` for an abort or a database error but
        # not for any other exception from a save callback, so the promoted
        # file is removed here too.
        private def _guard_{{ name.id }}_attachment(continuation : Proc(Nil)) : Nil
          continuation.call
        rescue error
          _roll_back_{{ name.id }}_attachment
          raise error
        end

        private def _commit_{{ name.id }}_attachment : Nil
          {{ state }}.commit_save
        end

        private def _roll_back_{{ name.id }}_attachment : Nil
          return unless {{ state }}.changed?

          self.{{ column }} = {{ state }}.roll_back_save
        end

        private def _destroy_{{ name.id }}_attachment : Nil
          {{ state }}.commit_destroy
        end
      end

      # *singular* names the single-file helpers (`add_<singular>`,
      # `remove_<singular>`); by default it is *name* without a trailing "s".
      macro has_many_attached(name, uploader = Gemma::Uploader, singular = nil)
        {% state = "_#{name.id}_attachments".id %}
        {% column = "#{name.id}_data".id %}
        {% singular = (singular || name.id.stringify.gsub(/s$/, "")).id %}

        column {{ column }} : Array(Gemma::UploadedFile)?, converter: Gemma::Grant::AttachmentListConverter, column_type: "TEXT"

        @[JSON::Field(ignore: true)]
        @[YAML::Field(ignore: true)]
        @{{ state }} : Gemma::Grant::AttachmentList?

        private def {{ state }} : Gemma::Grant::AttachmentList
          @{{ state }} ||= Gemma::Grant::AttachmentList.new(Proc(Gemma::Attacher).new { {{ uploader }}::Attacher.new }, {{ column }})
        end

        # Replaces every {{ name.id }} with *values* (uploads or cached
        # references). The old files are deleted after the save commits.
        def {{ name.id }}=(values : Array) : Nil
          {{ state }}.replace(values)
        end

        def {{ name.id }} : Array(Gemma::UploadedFile)
          {{ state }}.files
        end

        # Caches *value* and adds it to the list. Stored on `save`.
        def add_{{ singular }}(value) : Nil
          {{ state }}.add(value)
        end

        # Takes *file* out of the list. It is deleted after the save commits;
        # without a save, nothing is deleted.
        def remove_{{ singular }}(file : Gemma::UploadedFile) : Nil
          {{ state }}.remove(file)
        end

        # Empties the list. The files are deleted after the save commits.
        def clear_{{ name.id }} : Nil
          {{ state }}.clear
        end

        def {{ name.id }}_changed? : Bool
          {{ state }}.changed?
        end

        before_save :_prepare_{{ name.id }}_attachments
        around_save :_guard_{{ name.id }}_attachments
        after_save_commit :_commit_{{ name.id }}_attachments
        after_rollback :_roll_back_{{ name.id }}_attachments
        after_destroy_commit :_destroy_{{ name.id }}_attachments

        private def _prepare_{{ name.id }}_attachments : Nil
          return unless {{ state }}.changed?

          self.{{ column }} = {{ state }}.prepare_save
        end

        private def _guard_{{ name.id }}_attachments(continuation : Proc(Nil)) : Nil
          continuation.call
        rescue error
          _roll_back_{{ name.id }}_attachments
          raise error
        end

        private def _commit_{{ name.id }}_attachments : Nil
          {{ state }}.commit_save
        end

        private def _roll_back_{{ name.id }}_attachments : Nil
          return unless {{ state }}.changed?

          self.{{ column }} = {{ state }}.roll_back_save
        end

        private def _destroy_{{ name.id }}_attachments : Nil
          {{ state }}.commit_destroy
        end
      end
    end
  end
end
