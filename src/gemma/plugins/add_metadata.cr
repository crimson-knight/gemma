class Gemma
  module Plugins
    # Adds custom fields to every upload's metadata, computed from the
    # upload's first bytes (`Gemma::SNIFF_BYTES`).
    #
    # Each block can read `io`, an `IO::Memory` over those bytes, and
    # returns either a `String` (stored under the declared name) or a
    # `Hash(String, String)` (each entry stored under its own key). Custom
    # fields go to `Metadata#extra`; built-in fields (`size`, `mime_type`,
    # `width`, `height`, `filename`) are read from the bytes and cannot be
    # set this way.
    #
    # ```
    # class DocumentUploader < Gemma
    #   load_plugin Gemma::Plugins::AddMetadata
    #
    #   add_metadata :first_line, -> { io.gets || "" }
    #
    #   finalize_plugins!
    # end
    # ```
    module AddMetadata
      module InstanceMethods
        CUSTOM_METADATA_FIELDS = {} of Nil => Nil

        def extract_metadata(prefix : Bytes, metadata : Metadata) : Metadata
          metadata = super
          {% for name, decl in CUSTOM_METADATA_FIELDS %}
            io = IO::Memory.new(prefix, writable: false)
            add_custom_metadata(metadata, {{ name.stringify }}, {{ decl }}.call)
          {% end %}
          metadata
        end

        private def add_custom_metadata(metadata : Metadata, name : String, value : String) : Nil
          store_custom_field(metadata, name, value)
        end

        private def add_custom_metadata(metadata : Metadata, name : String, values : Hash(String, String)) : Nil
          values.each { |key, value| store_custom_field(metadata, key, value) }
        end

        private def store_custom_field(metadata : Metadata, key : String, value : String) : Nil
          if Metadata::BUILT_IN_KEYS.includes?(key)
            Log.warn { "add_metadata ignored #{key.inspect}: Gemma reads it from the file" }
          else
            metadata.extra[key] = value
          end
        end

        macro add_metadata(name, decl)
          {%
            name = name.id
            CUSTOM_METADATA_FIELDS[name] = decl
          %}
        end
      end
    end
  end
end
