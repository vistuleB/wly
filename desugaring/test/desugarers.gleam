import argv
import desugaring/assertive_testing
import gleam/io

pub fn main() {
  io.println("")
  let args = argv.load().arguments
  assertive_testing.run_assertive_desugarer_tests_on(args)
}
