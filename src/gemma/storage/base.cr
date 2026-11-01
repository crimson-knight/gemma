module Gemma
  module Storage
    # The contract every storage implements. A storage only ever receives an
    # `IO` to read from; the uploader opens an `UploadedFile` source and
    # streams it, so no storage needs to know about other storages.
    abstract class Base
      # Copies everything *io* has left into the location *id*. *metadata*
      # describes the file (a storage may turn `filename` and `mime_type`
      # into headers). The storage never closes *io*.
      abstract def upload(io : IO, id : String, metadata : Metadata = Metadata.new) : Nil

      # Returns the file at *id* opened for reading. The caller closes it.
      # Raises `Gemma::FileNotFound` when there is no such file.
      abstract def open(id : String) : IO

      # Returns a URL to the file at *id*; storages document the options
      # they accept.
      abstract def url(id : String, **options) : String

      # Returns whether a file exists at *id*.
      abstract def exists?(id : String) : Bool

      # Deletes the file at *id*. Deleting a missing file is not an error.
      abstract def delete(id : String) : Nil
    end
  end
end
