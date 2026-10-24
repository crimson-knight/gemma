require "../spec_helper"

# A row as Gemma 0.6 wrote it: `MetadataType` was a union hash, so numbers
# could be stored as JSON numbers or strings, and missing fields as null.
GEMMA_06_ROW = <<-JSON
  {"id":"9f2c4e1ab3d84f6e8a7b0c1d2e3f4a5b.png","storage_key":"store",
   "metadata":{"filename":"avatar.png","size":753,"mime_type":"image/png",
               "width":300,"height":"300","camera":"x100","rating":5,"blank":null}}
  JSON

describe Gemma::Metadata do
  it "loads a row written by Gemma 0.6" do
    file = Gemma::UploadedFile.from_json(GEMMA_06_ROW)

    file.id.should eq("9f2c4e1ab3d84f6e8a7b0c1d2e3f4a5b.png")
    file.storage_key.should eq("store")
    file.original_filename.should eq("avatar.png")
    file.size.should eq(753_i64)
    file.mime_type.should eq("image/png")
    file.dimensions.should eq({300, 300})
    file.metadata.extra.should eq({"camera" => "x100", "rating" => "5"})
  end

  it "writes the 0.6 row back with typed numbers and the same keys" do
    reloaded = JSON.parse(Gemma::UploadedFile.from_json(GEMMA_06_ROW).to_json)

    reloaded["metadata"].as_h.keys.sort!.should eq(["camera", "filename", "height", "mime_type", "rating", "size", "width"])
    reloaded["metadata"]["height"].as_i.should eq(300)
    Gemma::UploadedFile.from_json(reloaded.to_json).metadata.should eq(Gemma::UploadedFile.from_json(GEMMA_06_ROW).metadata)
  end

  it "loads a custom number past Int64, which Gemma 0.6 stored as UInt64" do
    file = Gemma::UploadedFile.from_json(%({"id":"a","storage_key":"store","metadata":{"counter":18446744073709551615,"ratio":0.5}}))

    file.metadata.extra.should eq({"counter" => "18446744073709551615", "ratio" => "0.5"})
  end

  it "gives no size for a size past Int64" do
    Gemma::UploadedFile.from_json(%({"id":"a","storage_key":"store","metadata":{"size":18446744073709551615}})).size.should be_nil
  end

  it "loads a row with a string size" do
    Gemma::UploadedFile.from_json(%({"id":"a","storage_key":"store","metadata":{"size":"50"}})).size.should eq(50_i64)
  end

  it "loads a row without metadata" do
    Gemma::UploadedFile.from_json(%({"id":"a","storage_key":"store"})).metadata.should eq(Gemma::Metadata.new)
  end

  it "skips nested values, which Gemma never writes" do
    metadata = Gemma::Metadata.from_json(%({"size":1,"nested":{"a":1},"list":[1]}))

    metadata.size.should eq(1_i64)
    metadata.extra.should be_empty
  end

  it "never writes an extra key over a built-in field" do
    metadata = Gemma::Metadata.new(size: 5_i64)
    metadata.extra["size"] = "999"

    JSON.parse(metadata.to_json)["size"].as_i.should eq(5)
  end
end
