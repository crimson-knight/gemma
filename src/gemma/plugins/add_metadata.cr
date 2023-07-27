class Gemma
  module Plugins
    module AddMetadata
      module InstanceMethods
        CUSTOM_METATADATA_FIELDS = {} of Nil => Nil

        private def extract_custom_metadata(io : IO, **options) : Gemma::UploadedFile::MetadataType
          custom_metadata = Gemma::UploadedFile::MetadataType.new

          {% for name, decl in CUSTOM_METATADATA_FIELDS %}
            result = {{decl}}.call

            if result.is_a?(Gemma::UploadedFile::MetadataType)
              custom_metadata = custom_metadata.merge(result)
            else
              data = Gemma::UploadedFile::MetadataType.new
              data["{{name}}"] = result
              custom_metadata = custom_metadata.merge(data)
            end

          {% end %}

          io.rewind

          custom_metadata
        end

        private def extract_metadata(io, **options) : Gemma::UploadedFile::MetadataType
          metadata = super
          metadata.merge(extract_custom_metadata(io, **options.merge(metadata: metadata)))
        end

        macro add_metadata(name, decl)
          {%
            name = name.id
            CUSTOM_METATADATA_FIELDS[name] = decl
          %}
        end
      end
    end
  end
end
