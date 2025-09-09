import gleam/io
import gleam/list
import gleam/result
import gleam/string.{length as len}
import simplifile.{type FileError}
import blame.{type Blame} as bl

pub type InputLine {
  InputLine(
    blame: Blame,
    indent: Int,
    suffix: String,
  )
}

pub type OutputLine {
  OutputLine(
    blame: Blame,
    indent: Int,
    suffix: String,
  )
}

// *************
// private utils
// *************

fn spaces(i: Int) -> String {
  string.repeat(" ", i)
}

// ***************************************************
// String -> List(InputLine) & path -> List(InputLine)
// ***************************************************

pub fn string_to_input_lines(
  source: String,
  path: String,
  added_indentation: Int,
) -> List(InputLine) {
  string.split(source, "\n")
  |> list.index_map(
    fn (s, i) {
      let suffix =
        string.trim_start(s)
        |> string.replace("\r", "")
      let indent = len(s) - len(suffix)
      InputLine(
        blame: bl.Src(
          comments: [],
          path: path,
          line_no: i + 1,
          char_no: indent + 1, // ...to match VSCode numbering
        ),
        indent: indent + added_indentation,
        suffix: suffix,
      )
    }
  )
}

pub fn read(
  path: String,
  added_indentation: Int,
) -> Result(List(InputLine), FileError) {
  simplifile.read(path)
  |> result.map(string_to_input_lines(_, path, added_indentation))
}

// **************************************************
// List(InputLine) -> List(OutputLine)
// **************************************************

pub fn input_lines_to_output_lines(
  lines: List(InputLine)
) -> List(OutputLine) {
  lines
  |> list.map(fn(l){OutputLine(l.blame, l.indent, l.suffix)})
}

// **************************************************
// OutputLine -> String & List(OutputLine) -> String
// **************************************************

pub fn output_lines_to_string(lines: List(OutputLine)) -> String {
  lines
  |> list.map(fn(c) {spaces(c.indent) <> c.suffix})
  |> string.join("\n")
}

// **************************************************
// List(OutputLine) & List(InputLine) pretty-printer (no1)
// **************************************************

pub fn input_lines_annotated_table_at_indent(
  content: List(InputLine),
  banner: String,
  indent: Int,
) -> List(String) {
  let margin = spaces(indent)
  content
  |> list.map(fn(c) {#(c.blame, spaces(c.indent) <> c.suffix)})
  |> bl.blamed_strings_annotated_table_no1(banner)
  |> list.map(fn(s) {margin <> s})
}

pub fn output_lines_annotated_table_at_indent(
  content: List(OutputLine),
  banner: String,
  indent: Int,
) -> List(String) {
  let margin = spaces(indent)
  content
  |> list.map(fn(c) {#(c.blame, spaces(c.indent) <> c.suffix)})
  |> bl.blamed_strings_annotated_table_no1(banner)
  |> list.map(fn(s) {margin <> s})
}

// **************************************************
// echo_output_lines & echo_input_lines
// **************************************************

pub fn echo_output_lines(
  lines: List(OutputLine),
  banner: String,
) -> List(OutputLine) {
  lines
  |> output_lines_annotated_table_at_indent(banner, 0)
  |> string.join("\n")
  |> io.println
  lines
}

pub fn echo_input_lines(
  lines: List(InputLine),
  banner: String,
) -> List(InputLine) {
  lines
  |> input_lines_annotated_table_at_indent(banner, 0)
  |> string.join("\n")
  |> io.println
  lines
}

pub fn main() {
  io.println("Hello from blamedlines!")
}
