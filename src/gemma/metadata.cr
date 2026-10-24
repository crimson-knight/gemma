require "json"

class Gemma
  # What Gemma knows about a stored file. Gemma reads `size`, `mime_type`,
  # `width` and `height` from the file's bytes; `filename` is the client's
  # original name (sanitized); `extra` holds an app's custom fields.
  #
  # The JSON shape is the one Gemma has always stored: one flat object, with
  # custom fields next to the built-in ones:
  #
  # ```json
  # {"filename": "a.png", "size": 753, "mime_type": "image/png", "width": 300, "height": 300, "custom": "value"}
  # ```
  #
  # Rows written by Gemma 0.6 load unchanged: a number written as a string
  # (`"size": "50"`) is read as a number, a custom number becomes its string
  # form in `extra`, and `null` fields are skipped.
  struct Metadata
    property filename : String?
    property size : Int64?
    property mime_type : String?
    property width : Int32?
    property height : Int32?
    property extra : Hash(String, String)

    BUILT_IN_KEYS = {"filename", "size", "mime_type", "width", "height"}

    def initialize(@filename : String? = nil, @size : Int64? = nil, @mime_type : String? = nil, @width : Int32? = nil, @height : Int32? = nil, @extra : Hash(String, String) = Hash(String, String).new)
    end

    def self.new(pull : JSON::PullParser)
      metadata = new
      pull.read_object do |key|
        case key
        when "filename"  then metadata.filename = read_string?(pull)
        when "size"      then metadata.size = read_integer?(pull)
        when "mime_type" then metadata.mime_type = read_string?(pull)
        when "width"     then metadata.width = read_dimension?(pull)
        when "height"    then metadata.height = read_dimension?(pull)
        else
          if value = read_string?(pull)
            metadata.extra[key] = value
          end
        end
      end
      metadata
    end

    def to_json(json : JSON::Builder) : Nil
      json.object do
        json.field "filename", filename
        json.field "size", size
        json.field "mime_type", mime_type
        json.field "width", width if width
        json.field "height", height if height
        extra.each do |key, value|
          json.field key, value unless BUILT_IN_KEYS.includes?(key)
        end
      end
    end

    # Width and height together, when both are known.
    def dimensions : {Int32, Int32}?
      known_width = width
      known_height = height
      {known_width, known_height} if known_width && known_height
    end

    # Reads a string, or the text of a number or boolean; nil for null and
    # for nested values, which Gemma never writes.
    private def self.read_string?(pull : JSON::PullParser) : String?
      case pull.kind
      when .string? then pull.read_string
      when .int?, .float?
        # The number's own text, so a value past Int64 (Gemma 0.6 stored
        # UInt64) loads unchanged.
        pull.read_raw
      when .bool? then pull.read_bool.to_s
      else
        pull.skip
        nil
      end
    end

    # Reads a width or height: an integer that fits an `Int32`, else nil.
    private def self.read_dimension?(pull : JSON::PullParser) : Int32?
      value = read_integer?(pull)
      value.to_i32 if value && value.in?(0_i64..Int32::MAX.to_i64)
    end

    # Reads an integer, or a string holding one; nil for anything else.
    private def self.read_integer?(pull : JSON::PullParser) : Int64?
      case pull.kind
      when .int?    then pull.read_raw.to_i64?
      when .string? then pull.read_string.to_i64?
      else
        pull.skip
        nil
      end
    end
  end
end
