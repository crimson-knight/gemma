# Registers an example for a confirmed defect that is not fixed yet.
#
# The block holds the assertion that fixed code must satisfy. While the defect
# is open the assertion fails, and the example reports as pending with the
# failure message, so the suite stays green and its output shows the defect
# still reproduces. Once a change makes the assertion pass, the example fails
# and asks for `it_reproduces_known_defect` to become a plain `it`.
#
# Only `should` failures count as the defect reproducing. Setup inside the
# block must not use `should`: raise instead (`record.save || raise "..."`),
# so a broken setup errors the example rather than passing as "pending".
#
# ```
# it_reproduces_known_defect "keeps the caller's IO open", fixed_in: "PR 4" do
#   io = tempfile("x")
#   uploader.upload(io)
#   io.closed?.should be_false
# end
# ```
def it_reproduces_known_defect(description : String, *, fixed_in : String, file = __FILE__, line = __LINE__, end_line = __END_LINE__, &block : ->)
  it(description, file: file, line: line, end_line: end_line) do
    begin
      block.call
    rescue error : Spec::AssertionFailed
      reason = error.message.to_s.lines.first? || "assertion failed"
      # GEMMA_SHOW_KNOWN_DEFECTS=1 prints why each defect still reproduces.
      STDOUT.puts "\n  [known defect] #{description}: #{reason}" if ENV["GEMMA_SHOW_KNOWN_DEFECTS"]?
      pending!("known defect (fix lands in #{fixed_in}): #{reason}", file, line)
    end

    fail "the defect no longer reproduces: change `it_reproduces_known_defect` to `it`", file, line
  end
end
