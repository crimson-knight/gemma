require "../../src/gemma"

metadata : Gemma::UploadedFile::MetadataType = Gemma::UploadedFile::MetadataType.new
uploaded_file = Gemma::UploadedFile.new("avatar.png", "store", metadata)

file_id : String = uploaded_file.id
storage_key : String = uploaded_file.storage_key
file_metadata : Gemma::UploadedFile::MetadataType = uploaded_file.metadata
file_url : String = uploaded_file.url
file_storage : Gemma::Storage::Base = uploaded_file.storage
file_data : Hash(String, String | Gemma::UploadedFile::MetadataType) = uploaded_file.data
