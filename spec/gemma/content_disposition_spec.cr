require "../spec_helper"

describe Gemma::ContentDisposition do
  describe ".inline" do
    it "returns the bare disposition without a filename" do
      Gemma::ContentDisposition.inline.should eq("inline")
    end

    it "adds both filename parameters for an ASCII name" do
      Gemma::ContentDisposition.inline("racecar.jpg").should eq(%(inline; filename="racecar.jpg"; filename*=UTF-8''racecar.jpg))
    end
  end

  describe ".attachment" do
    it "returns the bare disposition without a filename" do
      Gemma::ContentDisposition.attachment.should eq("attachment")
    end

    it "keeps spaces in the quoted fallback and encodes them in filename*" do
      Gemma::ContentDisposition.attachment("my file.pdf").should eq(
        %(attachment; filename="my file.pdf"; filename*=UTF-8''my%20file.pdf))
    end
  end

  describe ".build" do
    it "replaces non-ASCII characters in the fallback and UTF-8 encodes filename*" do
      Gemma::ContentDisposition.build(Gemma::ContentDisposition::Disposition::Inline, "日本語.txt").should eq(
        %(inline; filename="%3F%3F%3F.txt"; filename*=UTF-8''%E6%97%A5%E6%9C%AC%E8%AA%9E.txt))
    end

    it "escapes quotes, backslashes and separators so the header cannot be split" do
      value = Gemma::ContentDisposition.build(Gemma::ContentDisposition::Disposition::Attachment, %(a"b\\c;d\r\ne.txt))

      value.should eq(%(attachment; filename="a%22b%5Cc%3Bd%0D%0Ae.txt"; filename*=UTF-8''a%22b%5Cc%3Bd%0D%0Ae.txt))
    end
  end
end
