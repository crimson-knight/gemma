require "../../src/gemma"

attacher = Gemma::Attacher.new
cached_file : Gemma::UploadedFile? = attacher.attach_cached(IO::Memory.new("cached"))
stored_file : Gemma::UploadedFile? = attacher.attach(IO::Memory.new("stored"), "store")
current_file : Gemma::UploadedFile? = attacher.file
is_attached : Bool = attacher.attached?
