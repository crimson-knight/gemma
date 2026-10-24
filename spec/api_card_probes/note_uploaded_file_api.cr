require "../../src/gemma"

metadata : Gemma::Metadata = Gemma::Metadata.new(filename: "avatar.png")
uploaded_file = Gemma::UploadedFile.new("avatar.png", "store", metadata)

file_id : String = uploaded_file.id
storage_key : String = uploaded_file.storage_key
file_metadata : Gemma::Metadata = uploaded_file.metadata
file_size : Int64? = uploaded_file.size
file_width : Int32? = uploaded_file.width
file_url : String = uploaded_file.url
file_storage : Gemma::Storage::Base = uploaded_file.storage
file_json : String = uploaded_file.to_json
