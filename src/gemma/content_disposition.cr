module Gemma
  # Builds `Content-Disposition` header values (RFC 6266) whose file name
  # survives any character set: a plain `filename` parameter with an ASCII
  # fallback, and a `filename*` parameter carrying the UTF-8 name encoded per
  # RFC 5987 (RFC 8187).
  #
  # ```
  # Gemma::ContentDisposition.inline("résumé.pdf")
  # # => "inline; filename=\"r%3Fsum%3F.pdf\"; filename*=UTF-8''r%C3%A9sum%C3%A9.pdf"
  # Gemma::ContentDisposition.attachment # => "attachment"
  # ```
  module ContentDisposition
    # Bytes escaped inside the quoted ASCII `filename` fallback.
    TRADITIONAL_ESCAPED_CHARACTER = /[^ A-Za-z0-9!#$+.^_`|~-]/
    # Bytes escaped in the RFC 5987 `filename*` value (everything outside
    # `attr-char`).
    RFC_5987_ESCAPED_CHARACTER = /[^A-Za-z0-9!#$&+.^_`|~-]/

    enum Disposition
      Inline
      Attachment
    end

    # Returns an `inline` disposition, with *filename* when given.
    def self.inline(filename : String? = nil) : String
      build(Disposition::Inline, filename)
    end

    # Returns an `attachment` disposition, with *filename* when given.
    def self.attachment(filename : String? = nil) : String
      build(Disposition::Attachment, filename)
    end

    # Returns the header value for *disposition* and *filename*.
    def self.build(disposition : Disposition, filename : String? = nil) : String
      disposition_type = disposition.to_s.downcase
      return disposition_type unless filename

      ascii_filename = percent_escape(ascii_fallback(filename), TRADITIONAL_ESCAPED_CHARACTER)
      utf8_filename = percent_escape(filename, RFC_5987_ESCAPED_CHARACTER)
      %(#{disposition_type}; filename="#{ascii_filename}"; filename*=UTF-8''#{utf8_filename})
    end

    # Replaces every non-ASCII character with `?`, for clients that only
    # read the plain `filename` parameter.
    private def self.ascii_fallback(filename : String) : String
      filename.gsub { |character| character.ascii? ? character : '?' }
    end

    private def self.percent_escape(text : String, pattern : Regex) : String
      text.gsub(pattern) do |match|
        String.build do |io|
          match.each_byte { |byte| io << '%' << byte.to_s(16, upcase: true).rjust(2, '0') }
        end
      end
    end
  end
end
