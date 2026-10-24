require "../spec_helper"

private README_PATH   = File.join(SnippetCompiler::REPOSITORY_ROOT, "README.md")
private README_MARKER = "<!-- The block below is compiled by spec/probes/json_any_probe_spec.cr. -->"

# Returns the first fenced Crystal block after the marker comment.
private def readme_grant_example : String
  after_marker = File.read(README_PATH).split(README_MARKER, 2)[1]? || fail("README lost the marker comment for the Grant example")
  block = after_marker.match(/```crystal\n(.*?)\n```/m) || fail("no Crystal block after the README marker")
  block[1]
end

# followup-10-evidence/json_any_probe.cr: the model the README documents
# (`column avatar_data : JSON::Any?`) did not compile.
describe "json_any probe" do
  it_reproduces_known_defect "compiles the Grant model the README documents", fixed_in: "PR 7 (Grant layer)" do
    result = SnippetCompiler.check <<-CRYSTAL
      require "gemma"
      require "sqlite3"
      require "grant"
      require "grant/adapter/sqlite"
      Grant::Connections << Grant::Adapter::Sqlite.new(name: "sqlite", url: "sqlite3::memory:")

      #{readme_grant_example}
      CRYSTAL

    result.should_succeed
  end
end
