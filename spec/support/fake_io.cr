# An in-memory upload that reports a client filename and content type, the
# way an HTTP multipart part does.
class FakeIO < IO::Memory
  getter original_filename : String?
  getter content_type : String?

  def initialize(content : String = "", filename : String? = nil, content_type : String? = nil)
    super(content.to_slice, writable: false)

    @original_filename = filename
    @content_type = content_type
  end
end
