require "../spec_helper"

# followup-10-evidence/traversal_probe.cr: cached-file JSON from a client
# named an id outside the storage root, and Gemma read /etc/hosts through it.
describe "traversal probe" do
  it_reproduces_known_defect "refuses cached-file JSON whose id climbs out of the storage root", fixed_in: "PR 4 (storage containment)" do
    with_file_system_storages do |_root|
      attacher = Gemma::Attacher.new
      climbing_id = "../" * 12 + "etc/hosts"

      expect_raises(Gemma::Error) do
        attacher.attach_cached(%({"id":"#{climbing_id}","storage_key":"cache","metadata":{}}))
        attacher.file.try(&.open(&.gets))
      end
    end
  end

  it_reproduces_known_defect "takes size and MIME type from the cached file, not from the client's JSON", fixed_in: "PR 4 (cached references)" do
    with_file_system_storages do |_root|
      cached = Gemma.upload(IO::Memory.new("four"), "cache")
      attacher = Gemma::Attacher.new
      attacher.attach_cached(%({"id":"#{cached.id}","storage_key":"cache","metadata":{"size":1,"mime_type":"image/png"}}))

      attached = attacher.file || fail("expected an attached file")
      attached.size.should eq(4)
      attached.mime_type.should_not eq("image/png")
    end
  end
end
