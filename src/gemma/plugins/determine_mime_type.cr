require "mime"

class Gemma
  module Plugins
    # Chooses how an uploader detects MIME types. Without this plugin Gemma
    # uses its built-in magic-byte sniffer (`Tools::MagicBytes`).
    #
    # - `Tools::MagicBytes`: the built-in sniffer.
    # - `Tools::File`: the `file(1)` command, fed the upload's first bytes.
    #   Opt-in; it needs `file` installed.
    # - `Tools::Mime`: the client filename's extension.
    # - `Tools::ContentType`: the client's declared `Content-Type`.
    #
    # `Mime` and `ContentType` are the client's claims, so they are used only
    # when the sniffer cannot identify the bytes, and never for a type a
    # browser runs (HTML, XHTML, XML, SVG, JavaScript): such a claim gives
    # `application/octet-stream`.
    #
    # ```
    # class DocumentUploader < Gemma
    #   load_plugin(Gemma::Plugins::DetermineMimeType,
    #     analyzer: Gemma::Plugins::DetermineMimeType::Tools::File)
    #
    #   finalize_plugins!
    # end
    # ```
    module DetermineMimeType
      DEFAULT_OPTIONS = {
        analyzer: Gemma::Plugins::DetermineMimeType::Tools::MagicBytes,
      }

      enum Tools
        MagicBytes
        File
        Mime
        ContentType
      end

      module ClassMethods
        # Detects the MIME type of *io* with the configured analyzer. Reads
        # the first `SNIFF_BYTES` of *io* and does not rewind it.
        def determine_mime_type(io : IO) : String?
          metadata = Metadata.new(filename: Gemma.client_filename(io))
          if declared = Gemma.declared_content_type(io)
            metadata.extra["declared_content_type"] = declared
          end
          prefix = Gemma.read_prefix(io, Gemma::SNIFF_BYTES)
          mime_type_analyzer.call(prefix, metadata)
        end

        # Returns the analyzer configured for this uploader.
        def mime_type_analyzer : MimeTypeAnalyzer
          MimeTypeAnalyzer.new(plugin_settings.determine_mime_type[:analyzer])
        end
      end

      module InstanceMethods
        def detect_mime_type(prefix : Bytes, metadata : Metadata) : String?
          self.class.mime_type_analyzer.call(prefix, metadata)
        end
      end

      class MimeTypeAnalyzer
        def initialize(@tool : Tools)
        end

        # Returns the MIME type of the upload whose first bytes are *prefix*.
        def call(prefix : Bytes, metadata : Metadata) : String?
          case @tool
          when Tools::File
            extract_with_file(prefix)
          when Tools::Mime
            client_claim(prefix, metadata.filename.try { |name| MIME.from_filename?(name) })
          when Tools::ContentType
            client_claim(prefix, metadata.extra["declared_content_type"]?)
          else
            Analyzers::MagicBytes.mime_type(prefix)
          end
        end

        # The sniffed type when the bytes are recognized; otherwise the
        # client's claim, unless it names active content.
        private def client_claim(prefix : Bytes, claim : String?) : String?
          if sniffed = Analyzers::MagicBytes.mime_type(prefix)
            return sniffed
          end
          return unless claim

          media_type = Gemma.media_type(claim)
          return unless media_type

          Analyzers::ACTIVE_CONTENT_TYPES.includes?(media_type) ? "application/octet-stream" : media_type
        end

        private def extract_with_file(prefix : Bytes) : String?
          # file(1) answers "application/x-empty" for no bytes.
          return if prefix.empty?

          stdout = IO::Memory.new
          stderr = IO::Memory.new
          status = begin
            Process.run("file", args: ["--mime-type", "--brief", "-"], output: stdout, error: stderr, input: IO::Memory.new(prefix, writable: false))
          rescue error : ::File::NotFoundError
            raise AnalyzerMissing.new("the file command-line tool is not installed", cause: error)
          end

          unless status.success?
            raise AnalyzerFailed.new("file command failed: #{stderr}")
          end

          stdout.to_s.strip.presence
        end
      end
    end
  end
end
