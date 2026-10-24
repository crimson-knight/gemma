require "./base"

class Gemma
  module Storage
    # Stores files under a directory on the local filesystem. Every id is
    # resolved inside that directory: an id that would land outside it
    # (`../`, an absolute path, a NUL byte) raises `Gemma::InvalidLocation`
    # before anything is read or written.
    class FileSystem < Storage::Base
      getter directory : String
      getter prefix : String?
      getter permissions : Int32
      getter directory_permissions : Int32
      getter? clean : Bool

      DEFAULT_PERMISSIONS           = 0o644
      DEFAULT_DIRECTORY_PERMISSIONS = 0o755

      # Initializes a storage for uploading to the filesystem.
      #
      # - *prefix*: a directory under *directory* that files go into; it is
      #   also the path `#url` returns.
      # - *permissions*: UNIX permissions for created files (default `0644`).
      # - *directory_permissions*: UNIX permissions for created directories
      #   (default `0755`).
      # - *clean*: delete directories that `#delete` leaves empty (default
      #   true). Turn it off if that causes too much filesystem load.
      def initialize(@directory : String, @prefix : String? = nil, @clean : Bool = true, @permissions : Int32 = DEFAULT_PERMISSIONS, @directory_permissions : Int32 = DEFAULT_DIRECTORY_PERMISSIONS)
        unless Dir.exists?(expanded_directory)
          Dir.mkdir_p(expanded_directory, mode: directory_permissions)
        end
      end

      # The absolute directory files are stored in: *directory* plus
      # *prefix*.
      def expanded_directory : String
        if subdirectory = relative_prefix
          File.expand_path(File.join(directory, subdirectory))
        else
          File.expand_path(directory)
        end
      end

      # Streams *io* into the file at *id*, creating directories as needed.
      def upload(io : IO, id : String, metadata : UploadedFile::MetadataType = UploadedFile::MetadataType.new) : Nil
        File.write(path!(id), io, perm: permissions)
      end

      # Opens the file at *id* for reading.
      def open(id : String) : IO
        File.open(path(id), mode: "rb")
      rescue error : File::NotFoundError
        raise Gemma::FileNotFound.new("file #{id.inspect} not found on storage", cause: error)
      end

      # Returns true if the file exists on the filesystem.
      def exists?(id : String) : Bool
        File.exists?(path(id))
      end

      # Returns the absolute path of the file at *id*, which is always inside
      # `#expanded_directory`. Raises `Gemma::InvalidLocation` for an id that
      # would resolve anywhere else.
      def path(id : String) : String
        root = Path[expanded_directory]
        if id.empty? || id.includes?('\0') || Path[id].absolute?
          raise InvalidLocation.new("location #{id.inspect} is not a relative path")
        end

        resolved = root.join(id).normalize
        unless resolved.parents.includes?(root)
          raise InvalidLocation.new("location #{id.inspect} resolves outside the storage directory")
        end

        resolved.to_s
      end

      # Returns a path for the file at *id*. With a *prefix*, the path starts
      # at the prefix (so *directory* can be the app's `public` folder);
      # without one it is the absolute filesystem path. *host* is put in
      # front of the path when given.
      def url(id : String, host : String? = nil, **options) : String
        file_path = path(id)
        subdirectory = relative_prefix
        url_path = subdirectory ? (Path["/"] / subdirectory / Path[file_path].relative_to(expanded_directory)).to_s : file_path
        host ? host + url_path : url_path
      end

      # Deletes the file, and by default the directories it leaves empty.
      def delete(id : String) : Nil
        file_path = path(id)
        File.delete?(file_path)
        clean_empty_directories(file_path) if clean?
      end

      # Removes empty directories from *file_path*'s parent upward, stopping
      # at `#expanded_directory`, which is never removed.
      private def clean_empty_directories(file_path : String) : Nil
        root = Path[expanded_directory]
        # `Path#parents` lists the topmost directory first; walk from the
        # file's own directory upward.
        Path[file_path].parents.reverse_each do |directory_path|
          break unless directory_path.parents.includes?(root)
          break unless Dir.exists?(directory_path) && Dir.empty?(directory_path)

          Dir.delete(directory_path)
        end
      end

      # Returns the path for *id* after creating its parent directories.
      private def path!(id : String) : String
        file_path = path(id)
        Dir.mkdir_p(Path[file_path].dirname, mode: directory_permissions)
        file_path
      end

      private def relative_prefix : String?
        if configured_prefix = prefix
          configured_prefix.lchop('/')
        end
      end
    end
  end
end
