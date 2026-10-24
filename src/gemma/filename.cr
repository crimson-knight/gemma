module Gemma
  # Cleans a client-supplied filename before Gemma stores it as metadata or
  # sends it in a `Content-Disposition` header.
  module Filename
    MAX_BYTES = 255

    # Bidirectional-text controls that can make "gpj.exe" display as
    # "exe.jpg".
    BIDI_CONTROLS = {'\u202A', '\u202B', '\u202C', '\u202D', '\u202E', '\u2066', '\u2067', '\u2068', '\u2069', '\u200E', '\u200F'}

    # Returns *filename* without directory components, control characters
    # or bidi overrides, cut to 255 bytes (keeping the extension), or nil
    # when nothing usable is left.
    #
    # ```
    # Gemma::Filename.sanitize("../../etc/passwd")        # => "passwd"
    # Gemma::Filename.sanitize("C:\\Users\\a\\photo.jpg") # => "photo.jpg"
    # Gemma::Filename.sanitize("   ")                     # => nil
    # ```
    def self.sanitize(filename : String?) : String?
      return unless filename

      cleaned = filename.scrub.split(/[\/\\]/).last
      cleaned = cleaned.gsub { |character| character.control? || BIDI_CONTROLS.includes?(character) ? "" : character }.strip
      return if cleaned.empty? || cleaned == "." || cleaned == ".."

      truncate(cleaned)
    end

    # Cuts *filename* to `MAX_BYTES`, keeping a short extension whole.
    private def self.truncate(filename : String) : String
      return filename if filename.bytesize <= MAX_BYTES

      extension = File.extname(filename)
      extension = "" if extension.bytesize > 16
      stem = filename.rchop(extension)
      stem = stem.byte_slice(0, MAX_BYTES - extension.bytesize).scrub("")
      stem + extension
    end
  end
end
