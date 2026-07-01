import gleam/list
import gleeunit/should
import io_lines

pub fn normalize_line_endings_test() {
  "one\r\ntwo\rthree"
  |> io_lines.normalize_line_endings
  |> should.equal("one\ntwo\nthree")
}

pub fn string_to_input_lines_normalizes_line_endings_test() {
  "one\r\n  two\rthree"
  |> io_lines.string_to_input_lines("test", 0)
  |> list.map(fn(line) { line.suffix })
  |> should.equal(["one", "two", "three"])
}
