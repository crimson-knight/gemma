module Gemma
  module Plugins
    # Removed in Gemma 0.7: `Attacher.from_column`, `Attacher#load_column`
    # and `Attacher#column_data` are built in and read and write the
    # `UploadedFile` JSON.
    @[Deprecated("Use the built-in Attacher.from_column, #load_column and #column_data.")]
    module Column
      macro included
        {% raise "Gemma 0.7 removed Gemma::Plugins::Column: Attacher.from_column, Attacher#load_column and Attacher#column_data are built in." %}
      end
    end
  end
end
