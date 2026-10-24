require "json"
require "../../src/gemma"
require "grant"
require "../../src/gemma/grant"

class GemmaAPICardImage < Grant::Base
  table :api_card_probe_images

  column id : Int64, primary: true

  include Gemma::Grant::Attachable

  has_one_attached :avatar
  has_many_attached :documents
end

image = GemmaAPICardImage.new
avatar : Gemma::UploadedFile? = image.avatar
avatar_url : String? = image.avatar_url
avatar_changed : Bool = image.avatar_changed?
image.avatar = IO::Memory.new("avatar")

image.add_document(IO::Memory.new("document"))
list_of_documents : Array(Gemma::UploadedFile) = image.documents
documents_changed : Bool = image.documents_changed?
document = Gemma::UploadedFile.new("document.pdf", "cache")
image.remove_document(document)
image.clear_documents
