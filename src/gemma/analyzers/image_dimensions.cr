class Gemma
  module Analyzers
    # Reads an image's width and height from its header bytes, without
    # decoding the image or running an external command. Supports PNG, GIF,
    # JPEG (baseline and progressive: it scans for the SOF marker), WebP
    # (lossy, lossless and extended) and BMP. Returns nil for anything else
    # or for a header cut off before the dimensions.
    #
    # ```
    # Gemma::Analyzers::ImageDimensions.dimensions(File.read("photo.png").to_slice) # => {300, 300}
    # ```
    module ImageDimensions
      # JPEG start-of-frame markers that carry dimensions (SOF0-SOF15 minus
      # DHT C4, JPG C8 and DAC CC).
      JPEG_FRAME_MARKERS = {0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF}

      # Returns `{width, height}` for the image *bytes* start with, or nil.
      def self.dimensions(bytes : Bytes) : {Int32, Int32}?
        found = case MagicBytes.mime_type(bytes)
                when "image/png"  then png(bytes)
                when "image/gif"  then gif(bytes)
                when "image/jpeg" then jpeg(bytes)
                when "image/webp" then webp(bytes)
                when "image/bmp"  then bmp(bytes)
                end
        return unless found

        width, height = found
        found if width > 0 && height > 0
      end

      # The IHDR chunk is always first: width and height are big-endian
      # 32-bit values at offsets 16 and 20.
      private def self.png(bytes : Bytes) : {Int32, Int32}?
        return unless bytes.size >= 24 && String.new(bytes[12, 4]) == "IHDR"

        {u32_be(bytes, 16), u32_be(bytes, 20)}
      end

      # The logical screen size: little-endian 16-bit values at offset 6.
      private def self.gif(bytes : Bytes) : {Int32, Int32}?
        return unless bytes.size >= 10

        {u16_le(bytes, 6), u16_le(bytes, 8)}
      end

      # Walks the marker segments until a start-of-frame segment, whose
      # height and width are big-endian 16-bit values after the precision
      # byte.
      private def self.jpeg(bytes : Bytes) : {Int32, Int32}?
        offset = 2
        while offset + 4 <= bytes.size
          return unless bytes[offset] == 0xFF
          offset = skip_fill_bytes(bytes, offset)
          return if offset >= bytes.size

          marker = bytes[offset].to_i
          offset += 1
          next if standalone_marker?(marker)
          # End of image, or start of scan: no frame header before it.
          return if marker == 0xD9 || marker == 0xDA
          return if offset + 2 > bytes.size

          segment_length = u16_be(bytes, offset)
          return if segment_length < 2

          if JPEG_FRAME_MARKERS.includes?(marker)
            return unless offset + 7 <= bytes.size
            return {u16_be(bytes, offset + 5), u16_be(bytes, offset + 3)}
          end

          offset += segment_length
        end
      end

      # Markers may be padded with any number of 0xFF fill bytes; returns the
      # offset of the marker code after them.
      private def self.skip_fill_bytes(bytes : Bytes, offset : Int32) : Int32
        while offset < bytes.size && bytes[offset] == 0xFF
          offset += 1
        end
        offset
      end

      # TEM and RST0-RST7 carry no length.
      private def self.standalone_marker?(marker : Int32) : Bool
        marker == 0x01 || (0xD0..0xD7).includes?(marker)
      end

      # `VP8 ` (lossy) stores 14-bit sizes after a start code, `VP8L`
      # (lossless) packs 14-bit sizes minus one into four bytes, and `VP8X`
      # (extended) stores 24-bit sizes minus one.
      private def self.webp(bytes : Bytes) : {Int32, Int32}?
        return unless bytes.size >= 30

        case String.new(bytes[12, 4])
        when "VP8 "
          return unless bytes[23] == 0x9D && bytes[24] == 0x01 && bytes[25] == 0x2A
          {u16_le(bytes, 26) & 0x3FFF, u16_le(bytes, 28) & 0x3FFF}
        when "VP8L"
          return unless bytes[20] == 0x2F
          packed = bytes[21].to_u32 | (bytes[22].to_u32 << 8) | (bytes[23].to_u32 << 16) | (bytes[24].to_u32 << 24)
          {((packed & 0x3FFF) + 1).to_i32, (((packed >> 14) & 0x3FFF) + 1).to_i32}
        when "VP8X"
          {u24_le(bytes, 24) + 1, u24_le(bytes, 27) + 1}
        end
      end

      # BITMAPINFOHEADER and later: signed little-endian 32-bit width and
      # height at offset 18; a negative height means top-down rows.
      private def self.bmp(bytes : Bytes) : {Int32, Int32}?
        return unless bytes.size >= 26

        header_size = u32_le(bytes, 14)
        if header_size == 12
          {u16_le(bytes, 18), u16_le(bytes, 20)}
        else
          {absolute(i32_le(bytes, 18)), absolute(i32_le(bytes, 22))}
        end
      end

      private def self.u16_be(bytes : Bytes, offset : Int32) : Int32
        (bytes[offset].to_i32 << 8) | bytes[offset + 1].to_i32
      end

      private def self.u16_le(bytes : Bytes, offset : Int32) : Int32
        bytes[offset].to_i32 | (bytes[offset + 1].to_i32 << 8)
      end

      private def self.u24_le(bytes : Bytes, offset : Int32) : Int32
        bytes[offset].to_i32 | (bytes[offset + 1].to_i32 << 8) | (bytes[offset + 2].to_i32 << 16)
      end

      # Returns a big-endian 32-bit value, or 0 when it does not fit an
      # Int32 (no real image is that large; 0 is rejected by `dimensions`).
      private def self.u32_be(bytes : Bytes, offset : Int32) : Int32
        value = (bytes[offset].to_u32 << 24) | (bytes[offset + 1].to_u32 << 16) | (bytes[offset + 2].to_u32 << 8) | bytes[offset + 3].to_u32
        value <= Int32::MAX ? value.to_i32 : 0
      end

      private def self.u32_le(bytes : Bytes, offset : Int32) : Int32
        value = bytes[offset].to_u32 | (bytes[offset + 1].to_u32 << 8) | (bytes[offset + 2].to_u32 << 16) | (bytes[offset + 3].to_u32 << 24)
        value <= Int32::MAX ? value.to_i32 : 0
      end

      private def self.i32_le(bytes : Bytes, offset : Int32) : Int32
        (bytes[offset].to_u32 | (bytes[offset + 1].to_u32 << 8) | (bytes[offset + 2].to_u32 << 16) | (bytes[offset + 3].to_u32 << 24)).to_i32!
      end

      # The magnitude of *value*; 0 for Int32::MIN, which has none in Int32.
      private def self.absolute(value : Int32) : Int32
        value == Int32::MIN ? 0 : value.abs
      end
    end
  end
end
