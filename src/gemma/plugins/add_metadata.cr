module Gemma
  module Plugins
    # Removed in Gemma 0.7. Override `Gemma::Uploader#custom_metadata`
    # instead:
    #
    # ```
    # class DocumentUploader < Gemma::Uploader
    #   def custom_metadata(io : IO, metadata : Gemma::Metadata) : Hash(String, String)
    #     {"first_line" => io.gets || ""}
    #   end
    # end
    # ```
    @[Deprecated("Override Gemma::Uploader#custom_metadata instead.")]
    module AddMetadata
      macro included
        {% raise "Gemma 0.7 removed Gemma::Plugins::AddMetadata: override `def custom_metadata(io : IO, metadata : Gemma::Metadata) : Hash(String, String)` in your uploader." %}
      end
    end
  end
end
