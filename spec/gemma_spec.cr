require "./spec_helper"

describe Gemma do
  describe ".with_file" do
    context "given a file" do
      it "yields the given object" do
        existing_file = image

        Gemma.with_file(existing_file) do |file|
          file.should be_a(File)
          file.closed?.should be_false
          file.path.should eq(existing_file.path)
        end
      end
    end

    context "given an uploaded file instance" do
      it "downloads the uploaded file" do
        uploaded_file = uploader.upload(fakeio("uploaded_file"))

        Gemma.with_file(uploaded_file) do |file|
          file.should be_a(File)
          file.closed?.should be_false
          file.gets_to_end.should eq("uploaded_file")
        end
      end
    end

    context "given an io stream" do
      it "creates and yields a tempfile" do
        Gemma.with_file(fakeio("file_from_io")) do |file|
          file.should be_a(File)
          file.closed?.should be_false
          file.gets_to_end.should eq("file_from_io")
          file.path.should start_with(Dir.tempdir)
        end
      end
    end
  end
end
