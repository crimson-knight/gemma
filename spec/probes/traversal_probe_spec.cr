require "../spec_helper"
require "../../src/gemma/plugins/determine_mime_type"

# Reads MIME types from content with the `file` command, so the cached
# reference spec can tell "read from the stored bytes" apart from "missing".
class ContentMimeTypeUploader < Gemma
  load_plugin(Gemma::Plugins::DetermineMimeType,
    analyzer: Gemma::Plugins::DetermineMimeType::Tools::File)

  finalize_plugins!
end

# followup-10-evidence/traversal_probe.cr: cached-file JSON from a client
# named an id outside the storage root, and Gemma read /etc/hosts through it.
describe "traversal probe" do
  it "refuses cached-file JSON whose id climbs out of the storage root" do
    with_file_system_storages do |_root|
      attacher = Gemma::Attacher.new
      climbing_id = "../" * 12 + "etc/hosts"

      expect_raises(Gemma::InvalidLocation) do
        attacher.attach_cached(%({"id":"#{climbing_id}","storage_key":"cache","metadata":{}}))
      end
      attacher.file.should be_nil
    end
  end

  it "takes size and MIME type from the cached file, not from the client's JSON" do
    with_file_system_storages do |_root|
      png_bytes = image.getb_to_end
      cached = ContentMimeTypeUploader.upload(IO::Memory.new(png_bytes), "cache")
      attacher = ContentMimeTypeUploader::Attacher.new
      attacher.attach_cached(%({"id":"#{cached.id}","storage_key":"cache","metadata":{"size":1,"mime_type":"text/plain"}}))

      attached = attacher.file || raise "setup: nothing attached"
      attached.size.should eq(png_bytes.size)
      attached.mime_type.should eq("image/png")
    end
  end
end
