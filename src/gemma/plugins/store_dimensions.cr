module Gemma
  module Plugins
    # Records image width and height in each upload's metadata
    # (`Metadata#width`, `Metadata#height`). Files that are not images, or
    # whose header the analyzer cannot read, are stored without dimensions.
    #
    # - `Tools::Header` (default): Gemma's header reader for PNG, GIF, JPEG,
    #   WebP and BMP, with no external command.
    # - `Tools::Identify`: ImageMagick's `identify`, fed the upload's first
    #   bytes. Opt-in; it needs ImageMagick installed.
    #
    # ```
    # class AvatarUploader < Gemma::Uploader
    #   include Gemma::Plugins::StoreDimensions
    # end
    #
    # AvatarUploader.upload(png, "store").metadata.width # => 300
    # ```
    #
    # Choose `identify` by overriding `.dimensions_tool`:
    #
    # ```
    # class PosterUploader < Gemma::Uploader
    #   include Gemma::Plugins::StoreDimensions
    #
    #   def self.dimensions_tool : Gemma::Plugins::StoreDimensions::Tools
    #     Gemma::Plugins::StoreDimensions::Tools::Identify
    #   end
    # end
    # ```
    module StoreDimensions
      enum Tools
        Header
        Identify
      end

      macro included
        extend Gemma::Plugins::StoreDimensions::ClassMethods
      end

      module ClassMethods
        # The analyzer this uploader uses. Override it to choose another.
        def dimensions_tool : Tools
          Tools::Header
        end

        # Reads the dimensions of the image *io* starts with, raising
        # `Gemma::AnalyzerFailed` when it has none. Reads the first
        # `Gemma::SNIFF_BYTES` of *io* and does not rewind it.
        def extract_dimensions(io : IO) : {Int32, Int32}
          prefix = Gemma.read_prefix(io, Gemma::SNIFF_BYTES)
          dimensions_analyzer.call(prefix) || raise AnalyzerFailed.new("cannot read image dimensions")
        end

        def dimensions_analyzer : DimensionsAnalyzer
          DimensionsAnalyzer.new(dimensions_tool)
        end
      end

      def extract_metadata(prefix : Bytes, metadata : Metadata) : Metadata
        metadata = super
        if metadata.mime_type.try(&.starts_with?("image/"))
          if found = image_dimensions(prefix)
            metadata.width, metadata.height = found
          end
        end
        metadata
      end

      private def image_dimensions(prefix : Bytes) : {Int32, Int32}?
        self.class.dimensions_analyzer.call(prefix)
      rescue error : AnalyzerFailed
        Log.warn(exception: error) { "stored an image without dimensions" }
        nil
      end

      class DimensionsAnalyzer
        def initialize(@tool : Tools)
        end

        # Returns `{width, height}` for the image *prefix* starts with, or nil.
        def call(prefix : Bytes) : {Int32, Int32}?
          if @tool.identify?
            IdentifyAnalyzer.new(prefix).dimensions
          else
            Analyzers::ImageDimensions.dimensions(prefix)
          end
        end
      end

      # Runs ImageMagick's `identify` on an image's first bytes.
      class IdentifyAnalyzer
        def initialize(@prefix : Bytes)
        end

        def dimensions : {Int32, Int32}
          output = identify("-format", "%[fx:w] %[fx:h]\n")
          first_frame = output.lines.first? || ""
          values = first_frame.split.map(&.to_i32?)
          width = values[0]?
          height = values[1]?
          unless width && height && width > 0 && height > 0
            raise AnalyzerFailed.new("identify printed #{output.inspect}, not a width and a height")
          end

          {width, height}
        end

        private def identify(*args : String) : String
          stdout = IO::Memory.new
          stderr = IO::Memory.new
          status = begin
            Process.run("identify",
              args: [*args, "-"],
              output: stdout,
              error: stderr,
              input: IO::Memory.new(@prefix, writable: false)
            )
          rescue error : File::NotFoundError
            raise AnalyzerMissing.new("ImageMagick's identify command is not installed", cause: error)
          end

          raise AnalyzerFailed.new("identify command failed: #{stderr}") unless status.success?

          stdout.to_s.strip
        end
      end
    end
  end
end
