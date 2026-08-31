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
  assert_parses(["--track", "needle", "-verbatim", "+-5"])
  assert_parses(["--track", "needle", "-bc0", "-cc0", "+-5"])
  assert_parses(["--track", "needle", "+-5", "-bc10", "-cc20"])
  assert_parses(["--track", "needle", "-no-ellipses", "+-5"])
  assert_parses(["--dump", "120-"])
  assert_parses(["--dump", "-5--1"])
  assert_parses(["--dump", "!120-130"])
  assert_parses(["--dump", "-verbatim", "120-"])
  assert_parses(["--dump", "-bc0", "-cc0", "!120-130"])
  assert_parses(["--dump-assembled"])
  assert_parses(["--dump-parsed"])
  assert_parses(["--dump-filtered"])
  assert_parses(["--dump-splitter"])
  assert_parses(["--dump-splitter", "chapter", "appendix"])
  assert_parses(["--dump-emitter"])
  assert_parses(["--dump-emitter", "lecture-notes/05"])
  assert_parses([
    "--dump-splitter",
    "chapter",
    "--dump-splitter",
    "appendix",
    "--dump-emitter",
  ])
  assert_does_not_parse(["--dump-assembled", "unexpected"])
  assert_does_not_parse(["--dump-parsed", "unexpected"])
  assert_does_not_parse(["--dump-filtered", "unexpected"])
  assert_does_not_parse(["--echo-assembled"])
  assert_does_not_parse(["--echo-vxml-fragments"])
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
  assert_parses(["--track", "needle", "-verbatim", "-cc10", "-bc10"])
  assert_does_not_parse(["--track", "needle", "-bc-1"])
  assert_does_not_parse(["--track", "needle", "-cc"])
  assert_does_not_parse(["--track", "needle", "-bc10", "-bc20"])
  assert_does_not_parse([
    "--track",
    "needle",
    "-no-ellipses",
    "-no-ellipses",
  ])
  assert_does_not_parse(["--dump", "-no-ellipses"])
  assert_does_not_parse(["--dump", "-bc-1"])
  assert_does_not_parse(["--dump", "-cc"])
  assert_does_not_parse(["--dump", "-cc10", "-cc20"])
}
