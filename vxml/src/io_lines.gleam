//// Line-based input and output helpers.
////
//// `InputLine` and `OutputLine` pair indentation and text with `Blame`.
//// They provide a small bridge between files/strings and VXML parsers or
//// serializers.

import blame.{type Blame} as bl
import gleam/list
import gleam/result
import gleam/string.{length as len}
import simplifile.{type FileError}

/// A source line with indentation and blame.
pub type InputLine {
  InputLine(blame: Blame, indent: Int, suffix: String)
}

/// An output line with indentation and blame.
pub type OutputLine {
  OutputLine(blame: Blame, indent: Int, suffix: String)
}

// *************
// private utils
// *************

fn spaces(i: Int) -> String {
  string.repeat(" ", i)
}

/// Normalize CRLF and CR line endings to LF.
pub fn normalize_line_endings(source: String) -> String {
  source
  |> string.replace("\r\n", "\n")
  |> string.replace("\r", "\n")
}

// ***************************************************
// String -> List(InputLine) & path -> List(InputLine)
// ***************************************************

/// Convert a string to input lines, preserving source path and indentation.
pub fn string_to_input_lines(
  source: String,
  path: String,
  added_indentation: Int,
) -> List(InputLine) {
  source
  |> normalize_line_endings
  |> string.split("\n")
  |> list.index_map(fn(s, i) {
    let suffix = string.trim_start(s)
    let indent = len(s) - len(suffix)
    InputLine(
      blame: bl.Src(
        comments: [],
        path: path,
        line_no: i + 1,
        char_no: indent + 1,
        // ...to match VSCode numbering
        cursor: bl.Movable,
      ),
      indent: indent + added_indentation,
      suffix: suffix,
    )
  })
}

/// Read a file into input lines.
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

pub fn input_line_to_string(line: InputLine) -> String {
  spaces(line.indent) <> line.suffix
}

pub fn input_lines_to_string(lines: List(InputLine)) -> String {
  lines
  |> list.map(input_line_to_string)
  |> string.join("\n")
}

pub fn input_lines_to_output_lines(lines: List(InputLine)) -> List(OutputLine) {
  lines
  |> list.map(fn(l) { OutputLine(l.blame, l.indent, l.suffix) })
}

// **************************************************
// OutputLine -> String & List(OutputLine) -> String
// **************************************************

pub fn output_line_to_string(line: OutputLine) -> String {
  spaces(line.indent) <> line.suffix
}

/// Convert output lines to a newline-separated string.
pub fn output_lines_to_string(lines: List(OutputLine)) -> String {
  lines
  |> list.map(output_line_to_string)
  |> string.join("\n")
}

// **************************************************
// List(InputLine) -> String table pretty-printer &
// List(OutputLine) -> String table pretty-printer
// **************************************************

const default_blame_digest_margin = bl.BlameTableMarginColumnsMinMax(48, 48)

const default_comments_margin = bl.BlameTableMarginColumnsMinMax(30, 30)

pub fn input_lines_table(
  content: List(InputLine),
  banner: String,
  indent: Int,
) -> String {
  let margin = spaces(indent)
  content
  |> list.map(fn(c) { #(c.blame, spaces(c.indent) <> c.suffix) })
  |> bl.blamed_strings_annotated_table(
    banner,
    default_blame_digest_margin,
    default_comments_margin,
  )
  |> list.map(fn(s) { margin <> s })
  |> string.join("\n")
}

pub fn output_lines_table_lines_with(
  content: List(OutputLine),
  banner: String,
  indent: Int,
  blame_digest_margin: bl.BlameTableMarginColumnsMinMax,
  comments_margin: bl.BlameTableMarginColumnsMinMax,
) -> List(String) {
  let margin = spaces(indent)
  content
  |> list.map(fn(c) { #(c.blame, spaces(c.indent) <> c.suffix) })
  |> bl.blamed_strings_annotated_table(
    banner,
    blame_digest_margin,
    comments_margin,
  )
  |> list.map(fn(s) { margin <> s })
}

pub fn output_lines_table_lines(
  content: List(OutputLine),
  banner: String,
  indent: Int,
) -> List(String) {
  output_lines_table_lines_with(
    content,
    banner,
    indent,
    default_blame_digest_margin,
    default_comments_margin,
  )
}

pub fn output_lines_table_with(
  content: List(OutputLine),
  banner: String,
  indent: Int,
  blame_digest_margin: bl.BlameTableMarginColumnsMinMax,
  comments_margin: bl.BlameTableMarginColumnsMinMax,
) -> String {
  output_lines_table_lines_with(
    content,
    banner,
    indent,
    blame_digest_margin,
    comments_margin,
  )
  |> string.join("\n")
}

pub fn output_lines_table(
  content: List(OutputLine),
  banner: String,
  indent: Int,
) -> String {
  output_lines_table_lines(content, banner, indent)
  |> string.join("\n")
}
