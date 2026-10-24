require "../spec_helper"

# Plan headline 5 (no separate probe file): `require "gemma"` ran
# `Log.setup_from_env`, replacing the app's log backend and formatter.
describe "log setup probe" do
  it_reproduces_known_defect "leaves the app's Log configuration in place when Gemma is required", fixed_in: "PR 3 (library hygiene)" do
    result = SnippetCompiler.run <<-CRYSTAL
      require "log"

      APP_LOG_BACKEND = Log::MemoryBackend.new
      Log.setup(:info, APP_LOG_BACKEND)

      require "gemma"

      Log.for("app").info { "after gemma" }
      exit(APP_LOG_BACKEND.entries.size == 1 ? 0 : 1)
      CRYSTAL

    result.exit_code.should eq(0)
  end
end
