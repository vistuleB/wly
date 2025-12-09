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
          proxy: False,
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

pub fn output_line_to_string(line: OutputLine) -> String {
  spaces(line.indent) <> line.suffix
}

pub fn output_lines_to_string(lines: List(OutputLine)) -> String {
  lines
  |> list.map(output_line_to_string)
  |> string.join("\n")
}

// **************************************************
// List(InputLine) -> String table pretty-printer &
// List(OutputLine) -> String table pretty-printer
// **************************************************

pub fn input_lines_table(
  content: List(InputLine),
  banner: String,
  indent: Int,
) -> String {
  let margin = spaces(indent)
  content
  |> list.map(fn(c) {#(c.blame, spaces(c.indent) <> c.suffix)})
  |> bl.blamed_strings_annotated_table_no1(banner)
  |> list.map(fn(s) {margin <> s})
  |> string.join("\n")
}

pub fn output_lines_table_lines(
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

pub fn output_lines_table(
  content: List(OutputLine),
  banner: String,
  indent: Int,
) -> String {
  output_lines_table_lines(content, banner, indent)
  |> string.join("\n")
}
