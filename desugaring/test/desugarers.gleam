import argv
import assertive_testing

pub fn main() {
  let args = argv.load().arguments
  assertive_testing.run_assertive_desugarer_tests_on(args)
}
