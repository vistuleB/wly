import desugaring

fn assert_parses(arguments: List(String)) -> Nil {
  let assert Ok(_) = desugaring.process_command_line_arguments(arguments, [])
  Nil
}

fn assert_does_not_parse(arguments: List(String)) -> Nil {
  let assert Error(_) = desugaring.process_command_line_arguments(arguments, [])
  Nil
}

pub fn main() {
  assert_parses(["--track", "needle", "+-5", "-+2", "10-20"])
  assert_parses(["--track", "needle", "-1"])
  assert_parses(["--track", "needle", "+5-0"])
  assert_parses([
    "--track",
    "needle",
    "-with-ancestors",
    "-track+-1",
    "-print+-5",
  ])
  assert_parses(["--track", "needle", "-track+0", "+5-5"])
  assert_parses(["--track", "needle", "+0-0", "-print+5-5"])
  assert_parses(["--track", "needle", "-print+5-5"])
  assert_parses(["--track", "needle", "+5-5", "rename-5"])
  assert_parses(["--track", "needle", "+5-5", "rename+5"])
  assert_parses(["--track", "needle", "+5-5", "rename+5+10"])
  assert_parses(["--track", "needle", "+5-5", "rename-10-5"])
  assert_parses(["--track", "needle", "+5-5", "!rename-2+2"])
  assert_parses(["--dump", "120-"])
  assert_parses(["--dump", "-5--1"])
  assert_parses(["--dump", "!120-130"])
  assert_does_not_parse([
    "--track",
    "needle",
    "+5-5",
    "+2-2",
    "+20-30",
  ])
  assert_does_not_parse(["--track", "needle", "+5"])
  assert_does_not_parse([
    "--track",
    "needle",
    "+0-0",
    "+1-1",
    "+2-2",
  ])
  assert_does_not_parse([
    "--track",
    "needle",
    "-track+0",
    "-track+1-1",
  ])
}
