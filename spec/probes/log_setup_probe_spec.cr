require "../spec_helper"

# Plan headline 5 (no separate probe file): `require "gemma"` ran
# `Log.setup_from_env`, replacing the app's log backend and formatter.
describe "log setup probe" do
  it "leaves the app's log backend and formatter in place and sends Gemma's entries to them" do
    result = SnippetCompiler.run <<-CRYSTAL
      require "log"

      APP_LOG_OUTPUT = IO::Memory.new
      app_formatter = Log::Formatter.new do |entry, io|
        io << "APP|" << entry.source << "|" << entry.message
      end
      Log.setup(:info, Log::IOBackend.new(APP_LOG_OUTPUT, formatter: app_formatter, dispatcher: :sync))

      require "gemma"

      Log.for("app").info { "after gemma" }
      Gemma.warn("from gemma")
      print APP_LOG_OUTPUT.to_s
      CRYSTAL

    result.exit_code.should eq(0)
    result.output.should contain("APP|app|after gemma\nAPP|gemma|from gemma")
  end
end
