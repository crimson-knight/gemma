require "json"

module Gemma
  module Grant
    # Stores an attachment as its JSON in a TEXT column:
    # `{"id": "...", "storage_key": "store", "metadata": {...}}`.
    # `has_one_attached` declares its column with it.
    module AttachmentConverter
      extend self

      def to_db(value : Gemma::UploadedFile?) : ::Grant::Columns::Type
        value.try &.to_json
      end

      def from_db(value) : Gemma::UploadedFile?
        case value
        when String then Gemma::UploadedFile.from_json(value)
        when Slice  then Gemma::UploadedFile.from_json(String.new(value))
        end
      end

      def from_rs(result : ::DB::ResultSet) : Gemma::UploadedFile?
        json = result.read(String?)
        Gemma::UploadedFile.from_json(json) if json
      end
    end

    # Stores a list of attachments as a JSON array in a TEXT column.
    # `has_many_attached` declares its column with it.
    module AttachmentListConverter
      extend self

      def to_db(value : Array(Gemma::UploadedFile)?) : ::Grant::Columns::Type
        value.try &.to_json
      end

      def from_db(value) : Array(Gemma::UploadedFile)?
        case value
        when String then Array(Gemma::UploadedFile).from_json(value)
        when Slice  then Array(Gemma::UploadedFile).from_json(String.new(value))
        end
      end

      def from_rs(result : ::DB::ResultSet) : Array(Gemma::UploadedFile)?
        json = result.read(String?)
        Array(Gemma::UploadedFile).from_json(json) if json
      end
    end
  end
end
