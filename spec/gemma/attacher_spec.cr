require "../spec_helper"

describe Gemma::Attacher do
  before_each { reset_storages }

  describe "#promote_and_cleanup" do
    it "promotes a newly cached file to permanent storage" do
      attacher = Gemma::Attacher.new
      attacher.attach_cached(fakeio("cached"))

      attacher.promote_and_cleanup

      attacher.stored?.should be_true
      attacher.file.try(&.open(&.gets_to_end)).should eq("cached")
    end

    it "deletes the file it replaces" do
      attacher = Gemma::Attacher.new
      attacher.attach(fakeio("old"))
      previous_file = attacher.file || fail("expected an attached file")
      attacher.promote_and_cleanup

      attacher.attach_cached(fakeio("new"))
      attacher.promote_and_cleanup

      previous_file.exists?.should be_false
    end

    it "clears dirty tracking" do
      attacher = Gemma::Attacher.new
      attacher.attach_cached(fakeio)

      attacher.promote_and_cleanup

      attacher.changed?.should be_false
    end
  end

  it "has no finalize method for the garbage collector to call" do
    Gemma::Attacher.new.responds_to?(:finalize).should be_false
  end

  describe "#file!" do
    it "raises Gemma::NoFileAttached when nothing is attached" do
      expect_raises(Gemma::NoFileAttached) { Gemma::Attacher.new.file! }
    end
  end
end
