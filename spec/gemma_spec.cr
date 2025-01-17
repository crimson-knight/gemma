require "./spec_helper"

Spectator.describe Gemma do
  include GemmaHelpers
  include FileHelpers

  describe ".with_file" do
    context "given a file" do
      let(exiting_file) { image }

      it "yields the given object" do
        described_class.with_file(exiting_file) do |file|
          expect(file).to be_a(File)
          expect(file.closed?).to be_false
          expect(image.path).to eq(file.path)
        end
      end
    end

    context "given an uploaded file instance" do
      let(uploaded_file) { uploader.upload(fakeio("uploaded_file")) }

      it "downloads the uploaded file" do
        described_class.with_file(uploaded_file) do |file|
          expect(file).to be_a(File)
          expect(file.closed?).to be_false
          expect(file.gets_to_end).to eq("uploaded_file")
        end
      end
    end

    context "given an io stream" do
      let(file_from_io) { fakeio("file_from_io") }

      it "creates and yields a tempfile" do
        described_class.with_file(file_from_io) do |file|
          expect(file).to be_a(File)
          expect(file.closed?).to be_false
          expect(file.gets_to_end).to eq("file_from_io")
          expect(file.path).to match(/^#{Dir.tempdir}\/*/)
        end
      end
    end
  end
end
