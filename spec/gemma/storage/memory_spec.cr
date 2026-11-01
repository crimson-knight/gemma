require "../../spec_helper"

describe Gemma::Storage::Memory do
  describe "#store" do
    it "returns copies, so changing one never changes the stored content" do
      storage = Gemma::Storage::Memory.new
      storage.upload(IO::Memory.new("original"), "file.txt")

      snapshot = storage.store
      snapshot["file.txt"][0] = 'X'.ord.to_u8

      storage.open("file.txt").gets_to_end.should eq("original")
    end
  end
end
