require "../spec_helper"

describe Gemma::Filename do
  describe ".sanitize" do
    it "keeps an ordinary filename" do
      Gemma::Filename.sanitize("résumé photo.JPG").should eq("résumé photo.JPG")
    end

    it "keeps only the last path segment" do
      Gemma::Filename.sanitize("../../etc/passwd").should eq("passwd")
      Gemma::Filename.sanitize("C:\\Users\\me\\photo.png").should eq("photo.png")
    end

    it "removes control characters and bidi overrides" do
      Gemma::Filename.sanitize("a\nb\u0000c.txt").should eq("abc.txt")
      Gemma::Filename.sanitize("invoice\u202Efdp.exe").should eq("invoicefdp.exe")
    end

    it "gives nil when nothing usable is left" do
      Gemma::Filename.sanitize(nil).should be_nil
      Gemma::Filename.sanitize("   ").should be_nil
      Gemma::Filename.sanitize("uploads/..").should be_nil
    end

    it "cuts a long name to 255 bytes and keeps the extension" do
      sanitized = Gemma::Filename.sanitize("é" * 300 + ".jpeg")

      sanitized.should_not be_nil
      if sanitized
        sanitized.bytesize.should be <= 255
        sanitized.valid_encoding?.should be_true
        sanitized.should end_with(".jpeg")
      end
    end
  end
end
