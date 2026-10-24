# Compiles (and optionally runs) a standalone Crystal program, for specs whose
# subject is "this code compiles" or "this program behaves this way from its
# first line" (for example, what requiring Gemma does to the app's logger).
#
# The program is written under `spec/tmp/`. A line that requires Gemma the
# way an app does (`require "gemma"`, `require "gemma/grant"`) is rewritten to
# the checkout's `src/`, because the `crystal-alpha` wrapper fixes
# `CRYSTAL_PATH` to `lib` plus the stdlib. The compiler is `crystal-alpha`
# unless the `CRYSTAL` environment variable names another binary.
module SnippetCompiler
  # Raised by `run` when the program does not build, so an infrastructure
  # failure errors the example instead of reading as the behavior under test.
  class BuildFailed < Exception
  end

  REPOSITORY_ROOT   = File.expand_path("../..", __DIR__)
  SNIPPET_DIRECTORY = File.join(REPOSITORY_ROOT, "spec", "tmp")
  TIMED_OUT         = -1

  record Result, exit_code : Int32, output : String do
    # True when the compiler (and the program, for `run`) exited 0 and the
    # compiler printed no warning.
    def succeeded? : Bool
      exit_code == 0 && !output.includes?("Warning:")
    end

    def timed_out? : Bool
      exit_code == TIMED_OUT
    end

    # The compiler's error line, or the last line of output.
    def summary : String
      lines = output.lines.map(&.strip).reject(&.empty?)
      lines.find(&.starts_with?("Error:")) || lines.last? || "exit code #{exit_code}"
    end

    # Fails the current example with `summary` unless the snippet succeeded.
    def should_succeed : Nil
      fail(summary) unless succeeded?
    end
  end

  # Type-checks *source* without generating code.
  def self.check(source : String) : Result
    with_snippet_file(source) do |path|
      execute(compiler, ["build", "--no-codegen", "--no-color", path])
    end
  end

  # Builds *source*, then runs the program for at most *timeout*. The result
  # carries the program's exit code (`TIMED_OUT` when it was killed) and the
  # compiler's output followed by the program's. Raises `BuildFailed` when
  # the build fails or prints a warning.
  def self.run(source : String, timeout : Time::Span = 30.seconds) : Result
    with_snippet_file(source) do |path|
      binary_path = path.rchop(".cr")
      build = execute(compiler, ["build", "--no-color", path, "-o", binary_path])
      raise BuildFailed.new("snippet build failed: #{build.summary}") unless build.succeeded?

      begin
        program = execute(binary_path, [] of String, timeout)
        Result.new(program.exit_code, build.output + program.output)
      ensure
        File.delete?(binary_path)
        File.delete?("#{binary_path}.dwarf")
      end
    end
  end

  private def self.with_snippet_file(source : String, & : String -> Result) : Result
    Dir.mkdir_p(SNIPPET_DIRECTORY)
    path = File.join(SNIPPET_DIRECTORY, "snippet_#{Random::Secure.hex(6)}.cr")
    File.write(path, source.gsub(%(require "gemma), %(require "../../src/gemma)))
    begin
      yield path
    ensure
      File.delete?(path)
    end
  end

  private def self.execute(command : String, arguments : Array(String), timeout : Time::Span? = nil) : Result
    output = IO::Memory.new
    process = Process.new(command, arguments, output: output, error: output, chdir: REPOSITORY_ROOT)
    finished = Channel(Process::Status).new(1)
    spawn(name: "snippet-compiler-wait") { finished.send(process.wait) }

    select
    when status = finished.receive
      Result.new(status.exit_code, output.to_s)
    when timeout(timeout || 10.minutes)
      process.signal(Signal::KILL)
      finished.receive # reap the killed process before reading its output
      Result.new(TIMED_OUT, output.to_s + "\n(killed after #{timeout})")
    end
  end

  private def self.compiler : String
    ENV["CRYSTAL"]? || "crystal-alpha"
  end
end
