require "../spec_helper"

# followup-10-evidence/finalize_probe.cr: `Attacher#finalize` doubled as the
# GC finalizer, so collecting an abandoned attacher promoted its file. The
# probe runs in its own process because, while the defect is open, a
# collection that runs those finalizers can spin inside the collector and
# never return (seen while porting the suite: `GC_finish_collection` at 100%
# CPU), which would hang the whole spec run.
describe "finalize probe" do
  it_reproduces_known_defect "writes nothing to permanent storage when abandoned attachers are collected", fixed_in: "PR 3 (rename finalize)" do
    result = SnippetCompiler.run <<-CRYSTAL
      require "gemma"

      Gemma.configure do |config|
        config.storages["cache"] = Gemma::Storage::Memory.new
        config.storages["store"] = Gemma::Storage::Memory.new
      end

      def abandon_cached_attachers(count : Int32) : Nil
        count.times do
          attacher = Gemma::Attacher.new
          attacher.attach_cached(IO::Memory.new("abandoned upload"))
        end
      end

      abandon_cached_attachers(20)
      5.times { GC.collect }
      stored_count = Gemma.settings.storages["store"].as(Gemma::Storage::Memory).store.size
      puts "store objects after GC: \#{stored_count}"
      exit(stored_count == 0 ? 0 : 1)
      CRYSTAL

    result.output.should contain("store objects after GC: 0")
    result.exit_code.should eq(0)
  end
end
