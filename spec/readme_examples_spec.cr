require "./spec_helper"

private README_PATH = File.join(SnippetCompiler::REPOSITORY_ROOT, "README.md")

# Blocks after this marker need Grant and a database; their own probe
# compiles them.
private GRANT_MARKER = "compiled by spec/probes/json_any_probe_spec.cr"

# Names the README's fragments use without defining them.
private README_PRELUDE = <<-CRYSTAL
  record ReadmePart, file : File, filename : String?, headers : HTTP::Headers
  record ReadmeParams, files : Hash(String, ReadmePart)
  file = File.open(__FILE__)
  io = IO::Memory.new("readme")
  png = IO::Memory.new("readme")
  params = ReadmeParams.new({"avatar" => ReadmePart.new(file, "avatar.png", HTTP::Headers.new)})
  uploaded_file = Gemma::UploadedFile.new("readme.png", "store")
  client = Gemma::Storage::S3::Client.new("us-east-2", "key", "secret")
  storage = Gemma::Storage::S3.new(bucket: "bucket_name", client: client)
  CRYSTAL

# Each fenced Crystal block of the README, numbered from 1, without the
# ones the Grant probe compiles.
private def readme_crystal_blocks : Array({Int32, String})
  readme = File.read(README_PATH)
  blocks = [] of {Int32, String}
  readme.scan(/```crystal\n(?<body>.*?)```/m).each_with_index do |match, index|
    preceding = readme[0, match.begin(0)].lines.last(3).join
    next if preceding.includes?(GRANT_MARKER)

    blocks << {index + 1, match["body"]}
  end
  blocks
end

# One program holding every block, each in its own module so their classes
# and locals stay apart, with the README's `require` lines hoisted.
private def readme_program(blocks : Array({Int32, String})) : String
  requires = Set{"require \"gemma\""}
  String.build do |program|
    bodies = blocks.map do |number, body|
      code = body.lines.reject do |line|
        if line.starts_with?("require ")
          requires << line.strip
          true
        end
      end
      "module ReadmeBlock#{number}\n#{README_PRELUDE}\n#{code.join("\n")}\nend\n"
    end
    requires.each { |line| program << line << '\n' }
    bodies.each { |body| program << body }
  end
end

describe "README" do
  it "has Crystal examples that compile against this checkout" do
    blocks = readme_crystal_blocks
    blocks.size.should be > 10

    SnippetCompiler.check(readme_program(blocks)).should_succeed
  end
end
