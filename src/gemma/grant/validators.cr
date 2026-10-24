module Gemma
  module Grant
    # Attachment validations, registered through Grant's own validation
    # rules, so they take Grant's options (`on:`, `if:`, `unless:`,
    # `strict:`) and appear in `errors` like any other rule.
    #
    # ```
    # class User < Grant::Base
    #   include Gemma::Grant::Attachable
    #   include Gemma::Grant::AttachmentValidators
    #
    #   column id : Int64, primary: true
    #   has_one_attached :avatar
    #
    #   validates_attachment_presence_of :avatar
    #   validates_attachment_size_of :avatar, maximum: 5_000_000
    #   validates_attachment_type_of :avatar, accept: ["image/png", "image/jpeg"]
    #   validates_attachment_dimensions_of :avatar, width: 10..4000, height: 10..4000
    # end
    # ```
    #
    # A file whose size, type or dimensions Gemma could not read fails the
    # rule that needs them. On a `has_many_attached` list each rule checks
    # every file.
    module AttachmentValidators
      # Every file *value* holds: none, one, or a list.
      def self.files(value : Gemma::UploadedFile?) : Array(Gemma::UploadedFile)
        value ? [value] : [] of Gemma::UploadedFile
      end

      def self.files(value : Array(Gemma::UploadedFile)) : Array(Gemma::UploadedFile)
        value
      end

      # The patterns an `accept:`/`reject:` option names: one, or a list.
      def self.patterns(pattern : String) : Array(String)
        [pattern]
      end

      def self.patterns(list_of_patterns : Enumerable(String)) : Array(String)
        list_of_patterns.to_a
      end

      # Whether *mime_type* matches *pattern*: an exact type, or `type/*`.
      def self.type_matches?(mime_type : String, pattern : String) : Bool
        if pattern.ends_with?("/*")
          mime_type.starts_with?(pattern.rchop('*'))
        else
          mime_type == pattern
        end
      end

      # The attachment must be present (for a list: not empty).
      macro validates_attachment_presence_of(name, message = nil, **options)
        __rule({{ name }}, {{ message }} || "must be attached", :blank, kind: :presence, {{ options.double_splat }}) do
          !Gemma::Grant::AttachmentValidators.files(value).empty?
        end
      end

      # Each file's size, in bytes, must be within *minimum* and *maximum*.
      macro validates_attachment_size_of(name, maximum = nil, minimum = nil, message = nil, **options)
        {% if maximum %}
          __rule({{ name }}, {{ message }} || "is too large (maximum is #{{{ maximum }}} bytes)", :too_large, {{ options.double_splat }}) do
            Gemma::Grant::AttachmentValidators.files(value).all? do |file|
              size = file.size
              !size.nil? && size <= {{ maximum }}
            end
          end
        {% end %}
        {% if minimum %}
          __rule({{ name }}, {{ message }} || "is too small (minimum is #{{{ minimum }}} bytes)", :too_small, {{ options.double_splat }}) do
            Gemma::Grant::AttachmentValidators.files(value).all? do |file|
              size = file.size
              !size.nil? && size >= {{ minimum }}
            end
          end
        {% end %}
      end

      # Each file's detected MIME type must match one of *accept* and none
      # of *reject* (`"image/png"`, or `"image/*"`).
      macro validates_attachment_type_of(name, accept = nil, reject = nil, message = nil, **options)
        {% if accept %}
          __rule({{ name }}, {{ message }} || "has an invalid content type", :invalid_type, {{ options.double_splat }}) do
            Gemma::Grant::AttachmentValidators.files(value).all? do |file|
              mime_type = file.mime_type
              !mime_type.nil? && Gemma::Grant::AttachmentValidators.patterns({{ accept }}).any? { |pattern| Gemma::Grant::AttachmentValidators.type_matches?(mime_type, pattern) }
            end
          end
        {% end %}
        {% if reject %}
          __rule({{ name }}, {{ message }} || "has a forbidden content type", :forbidden_type, {{ options.double_splat }}) do
            Gemma::Grant::AttachmentValidators.files(value).all? do |file|
              mime_type = file.mime_type
              !mime_type.nil? && Gemma::Grant::AttachmentValidators.patterns({{ reject }}).none? { |pattern| Gemma::Grant::AttachmentValidators.type_matches?(mime_type, pattern) }
            end
          end
        {% end %}
      end

      # Each image's width and height must equal, or fall in, *width* and
      # *height* (an Int32 or a Range). Needs `Gemma::Plugins::StoreDimensions`.
      macro validates_attachment_dimensions_of(name, width = nil, height = nil, message = nil, **options)
        {% if width %}
          __rule({{ name }}, {{ message }} || "has an invalid width (must be #{{{ width }}} pixels)", :invalid_width, {{ options.double_splat }}) do
            Gemma::Grant::AttachmentValidators.files(value).all? do |file|
              actual = file.width
              !actual.nil? && ({{ width }} === actual)
            end
          end
        {% end %}
        {% if height %}
          __rule({{ name }}, {{ message }} || "has an invalid height (must be #{{{ height }}} pixels)", :invalid_height, {{ options.double_splat }}) do
            Gemma::Grant::AttachmentValidators.files(value).all? do |file|
              actual = file.height
              !actual.nil? && ({{ height }} === actual)
            end
          end
        {% end %}
      end

      # A `has_many_attached` list must hold at least *minimum* and at most
      # *maximum* files.
      macro validates_attachment_count_of(name, maximum = nil, minimum = nil, message = nil, **options)
        {% if maximum %}
          __rule({{ name }}, {{ message }} || "has too many files (maximum is #{{{ maximum }}})", :too_long, {{ options.double_splat }}) do
            Gemma::Grant::AttachmentValidators.files(value).size <= {{ maximum }}
          end
        {% end %}
        {% if minimum %}
          __rule({{ name }}, {{ message }} || "has too few files (minimum is #{{{ minimum }}})", :too_short, {{ options.double_splat }}) do
            Gemma::Grant::AttachmentValidators.files(value).size >= {{ minimum }}
          end
        {% end %}
      end

      # The 0.6 names, with their 0.6 argument shapes.
      @[Deprecated("Use validates_attachment_size_of.")]
      macro validate_file_size_of(name, maximum = nil, minimum = nil, message = nil)
        validates_attachment_size_of({{ name }}, maximum: {{ maximum }}, minimum: {{ minimum }}, message: {{ message }})
      end

      @[Deprecated("Use validates_attachment_type_of.")]
      macro validate_content_type_of(name, accept = nil, reject = nil, message = nil)
        validates_attachment_type_of({{ name }}, accept: {{ accept }}, reject: {{ reject }}, message: {{ message }})
      end

      @[Deprecated("Use validates_attachment_presence_of.")]
      macro validate_presence_of(name, message = nil)
        validates_attachment_presence_of({{ name }}, message: {{ message }})
      end

      @[Deprecated("Use validates_attachment_dimensions_of.")]
      macro validate_dimensions_of(name, width = nil, height = nil, message = nil)
        validates_attachment_dimensions_of({{ name }}, width: {{ width }}, height: {{ height }}, message: {{ message }})
      end

      @[Deprecated("Use validates_attachment_count_of.")]
      macro validate_collection_size_of(name, maximum = nil, minimum = nil, message = nil)
        validates_attachment_count_of({{ name }}, maximum: {{ maximum }}, minimum: {{ minimum }}, message: {{ message }})
      end
    end
  end
end
