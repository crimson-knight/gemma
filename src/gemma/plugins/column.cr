class Gemma
  module Plugins
    module Column
      # Turns an attacher's file into column data and back. Subclass it and
      # pass it as `column_serializer:` to store another format.
      abstract class BaseSerializer
        # Crystal has no abstract class methods, so the base raises.
        # https://github.com/crystal-lang/crystal/issues/5956
        def self.dump(file : UploadedFile?) : String?
          raise NotImplementedError.new("Implement method .dump")
        end

        def self.load(data : String) : UploadedFile
          raise NotImplementedError.new("Implement method .load")
        end
      end

      class JsonSerializer < BaseSerializer
        def self.dump(file : UploadedFile?) : String?
          file.try &.to_json
        end

        def self.load(data : String) : UploadedFile
          UploadedFile.from_json(data)
        end
      end

      DEFAULT_OPTIONS = {
        column_serializer: Gemma::Plugins::Column::JsonSerializer,
      }

      module AttacherClassMethods
        # Initializes the attacher from data stored in a database column.
        #
        # ```
        # Attacher.from_column(%({"id":"...","storage_key":"store","metadata":{}}))
        # ```
        def from_column(data : String?, **options) : Attacher
          attacher = new(**options)
          attacher.load_column(data)
          attacher
        end
      end

      module AttacherMethods
        # Column serializer class.
        getter column_serializer : Gemma::Plugins::Column::BaseSerializer.class

        # Allows overriding the default column serializer.
        def initialize(@column_serializer = self.class.gemma_class.plugin_settings.column[:column_serializer], **options)
          super(**options)
        end

        # Loads the attachment from column data (trusted: it is what Gemma
        # wrote).
        def load_column(data : String) : UploadedFile
          file = column_serializer.load(data)
          load_data(file)
          file
        end

        def load_column(data : Nil) : Nil
          load_data(nil)
        end

        # Returns the attached file serialized for the column (JSON by
        # default), or nil when nothing is attached.
        def column_data : String?
          column_serializer.dump(file)
        end
      end
    end
  end
end
