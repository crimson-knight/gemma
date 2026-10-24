class Gemma
  module Analyzers
    # Detects a file's MIME type from its first bytes ("magic numbers"),
    # without any external command. It recognizes the types apps accept
    # most: JPEG, PNG, GIF, WebP, BMP, TIFF, HEIC/HEIF, AVIF, PDF, MP3, M4A,
    # MP4, QuickTime, WebM, Ogg, WAV, FLAC, ZIP, SVG and plain UTF-8 text.
    # Anything else gives nil, which validators treat as "not accepted".
    #
    # ```
    # Gemma::Analyzers::MagicBytes.mime_type("\x89PNG\r\n\x1A\n...".to_slice) # => "image/png"
    # ```
    module MagicBytes
      # The canonical extension for each MIME type the sniffer reports, then
      # other extensions a client may legitimately use for it.
      EXTENSIONS = {
        "image/jpeg"      => {"jpg", "jpeg", "jpe"},
        "image/png"       => {"png"},
        "image/gif"       => {"gif"},
        "image/webp"      => {"webp"},
        "image/bmp"       => {"bmp"},
        "image/tiff"      => {"tiff", "tif"},
        "image/heic"      => {"heic"},
        "image/heif"      => {"heif"},
        "image/avif"      => {"avif"},
        "image/svg+xml"   => {"svg"},
        "application/pdf" => {"pdf"},
        "audio/mpeg"      => {"mp3"},
        "audio/mp4"       => {"m4a"},
        "audio/wav"       => {"wav"},
        "audio/flac"      => {"flac"},
        "audio/ogg"       => {"ogg", "oga", "opus"},
        "video/mp4"       => {"mp4", "m4v"},
        "video/quicktime" => {"mov"},
        "video/webm"      => {"webm"},
        "application/zip" => {"zip"},
        "text/plain"      => {"txt"},
      }

      HEIC_BRANDS = {"heic", "heix", "hevc", "hevx", "heim", "heis"}
      HEIF_BRANDS = {"mif1", "msf1", "heif"}
      AVIF_BRANDS = {"avif", "avis"}
      M4A_BRANDS  = {"M4A ", "M4B ", "M4P "}
      MOV_BRANDS  = {"qt  "}

      # Returns the MIME type *bytes* (the start of a file) identify, or nil.
      def self.mime_type(bytes : Bytes) : String?
        return if bytes.empty?

        image_type(bytes) || container_type(bytes) || document_type(bytes) || audio_type(bytes) || text_type(bytes)
      end

      # Returns the canonical extension (without the dot) for *mime_type*.
      def self.extension_for(mime_type : String) : String?
        EXTENSIONS[mime_type]?.try(&.first)
      end

      # Returns whether *extension* (without the dot, any case) is a usual
      # extension for *mime_type*.
      def self.extension_matches?(extension : String, mime_type : String) : Bool
        EXTENSIONS[mime_type]?.try(&.includes?(extension.downcase)) || false
      end

      private def self.image_type(bytes : Bytes) : String?
        if starts_with?(bytes, 0, Bytes[0xFF, 0xD8, 0xFF])
          "image/jpeg"
        elsif starts_with?(bytes, 0, Bytes[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
          "image/png"
        elsif ascii_at?(bytes, 0, "GIF87a") || ascii_at?(bytes, 0, "GIF89a")
          "image/gif"
        elsif ascii_at?(bytes, 0, "RIFF") && ascii_at?(bytes, 8, "WEBP")
          "image/webp"
        elsif ascii_at?(bytes, 0, "BM") && bytes.size >= 26
          "image/bmp"
        elsif starts_with?(bytes, 0, Bytes[0x49, 0x49, 0x2A, 0x00]) || starts_with?(bytes, 0, Bytes[0x4D, 0x4D, 0x00, 0x2A])
          "image/tiff"
        end
      end

      # ISO base media files (HEIC, AVIF, MP4, M4A, QuickTime) start with an
      # `ftyp` box whose major brand names the format; WebM and Matroska
      # share the EBML header.
      private def self.container_type(bytes : Bytes) : String?
        if ascii_at?(bytes, 4, "ftyp") && bytes.size >= 12
          brand = String.new(bytes[8, 4])
          if HEIC_BRANDS.includes?(brand)
            "image/heic"
          elsif HEIF_BRANDS.includes?(brand)
            "image/heif"
          elsif AVIF_BRANDS.includes?(brand)
            "image/avif"
          elsif M4A_BRANDS.includes?(brand)
            "audio/mp4"
          elsif MOV_BRANDS.includes?(brand)
            "video/quicktime"
          else
            "video/mp4"
          end
        elsif starts_with?(bytes, 0, Bytes[0x1A, 0x45, 0xDF, 0xA3])
          "video/webm"
        elsif starts_with?(bytes, 0, Bytes[0x50, 0x4B, 0x03, 0x04]) || starts_with?(bytes, 0, Bytes[0x50, 0x4B, 0x05, 0x06])
          "application/zip"
        end
      end

      private def self.document_type(bytes : Bytes) : String?
        if ascii_at?(bytes, 0, "%PDF-")
          "application/pdf"
        elsif svg?(bytes)
          "image/svg+xml"
        end
      end

      private def self.audio_type(bytes : Bytes) : String?
        if ascii_at?(bytes, 0, "ID3") || mpeg_audio_frame?(bytes)
          "audio/mpeg"
        elsif ascii_at?(bytes, 0, "RIFF") && ascii_at?(bytes, 8, "WAVE")
          "audio/wav"
        elsif ascii_at?(bytes, 0, "fLaC")
          "audio/flac"
        elsif ascii_at?(bytes, 0, "OggS")
          "audio/ogg"
        end
      end

      # UTF-8 text with no NUL bytes and no control characters other than
      # tab, newline, carriage return and form feed. A multi-byte character
      # cut off at the end of the sample still counts as text.
      private def self.text_type(bytes : Bytes) : String?
        sample = bytes
        return if sample.any? { |byte| byte < 0x20 && !{0x09_u8, 0x0A_u8, 0x0C_u8, 0x0D_u8}.includes?(byte) }
        return if sample.includes?(0x7F_u8)

        text = String.new(sample)
        if text.valid_encoding? || String.new(sample[0, trimmed_utf8_length(sample)]).valid_encoding?
          "text/plain"
        end
      end

      # The length of *bytes* without a trailing, incomplete UTF-8 sequence.
      private def self.trimmed_utf8_length(bytes : Bytes) : Int32
        length = bytes.size
        3.times do
          break if length == 0
          byte = bytes[length - 1]
          break if byte < 0x80
          length -= 1
          break if byte >= 0xC0
        end
        length
      end

      # An SVG is XML text whose first element is `<svg`. Only the start is
      # inspected, after an optional BOM, XML declaration, comments and
      # DOCTYPE.
      private def self.svg?(bytes : Bytes) : Bool
        head = String.new(bytes[0, Math.min(bytes.size, 1024)]).lstrip("﻿").lstrip
        return false unless head.starts_with?('<')

        head.matches?(/\A(?:<\?xml[^>]*>\s*)?(?:<!--.*?-->\s*)*(?:<!DOCTYPE[^>]*>\s*)?(?:<!--.*?-->\s*)*<svg[\s>]/mi)
      rescue ArgumentError
        false
      end

      # An MPEG audio frame header without an ID3 tag: 11 sync bits, then a
      # valid version, layer III, and a bitrate index that is not "bad".
      private def self.mpeg_audio_frame?(bytes : Bytes) : Bool
        return false if bytes.size < 3
        return false unless bytes[0] == 0xFF && (bytes[1] & 0xE0) == 0xE0

        version_bits = (bytes[1] >> 3) & 0x03
        layer_bits = (bytes[1] >> 1) & 0x03
        bitrate_index = bytes[2] >> 4
        version_bits != 0x01 && layer_bits == 0x01 && bitrate_index != 0x0F && bitrate_index != 0x00
      end

      private def self.starts_with?(bytes : Bytes, offset : Int32, expected : Bytes) : Bool
        bytes.size >= offset + expected.size && bytes[offset, expected.size] == expected
      end

      private def self.ascii_at?(bytes : Bytes, offset : Int32, expected : String) : Bool
        starts_with?(bytes, offset, expected.to_slice)
      end
    end
  end
end
