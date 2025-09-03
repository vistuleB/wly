import gleam/io
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/string.{inspect as ins}
import infrastructure.{type Desugarer}
import blame.{type Blame} as bl
import on

pub fn dashes(num: Int) -> String { string.repeat("-", num) }
pub fn solid_dashes(num: Int) -> String { string.repeat("─", num) }
pub fn spaces(num: Int) -> String { string.repeat(" ", num) }
pub fn dots(num: Int) -> String { string.repeat(".", num) }
pub fn threedots(num: Int) -> String { string.repeat("…", num) }
pub fn twodots(num: Int) -> String { string.repeat("‥", num) }

pub fn how_many(
  singular: String,
  plural: String,
  count: Int,
) -> String {
  case count {
    1 -> "1 " <> singular
    _ -> ins(count) <> " " <> plural
  }
}

// **********************
// 2-column table printer
// **********************

pub fn two_column_maxes(
  lines: List(#(String, String))
) -> #(Int, Int) {
  list.fold(
    lines,
    #(0, 0),
    fn(acc, pair) {
      #(
        int.max(acc.0, string.length(pair.0)),
        int.max(acc.1, string.length(pair.1)),
      )
    }
  )
}

pub fn two_column_table(
  lines: List(#(String, String)),
) -> List(String) {
  let maxes = two_column_maxes(lines)
  let padding = #(2, 2)
  let one_line = fn(cols: #(String, String)) -> String {
    "│ " <> cols.0 <> spaces(maxes.0 - string.length(cols.0) + padding.0) <>
    "│ " <> cols.1 <> spaces(maxes.1 - string.length(cols.1) + padding.1) <>
    "│"
  }
  let sds = #(
    solid_dashes(maxes.0 + padding.0),
    solid_dashes(maxes.1 + padding.1),
  )
  let assert [first, ..rest] = lines
  [
    [
      "┌─" <> sds.0 <> "┬─" <> sds.1 <> "┐",
      one_line(first),
      "├─" <> sds.0 <> "┼─" <> sds.1 <> "┤"
    ],
    list.map(rest, one_line),
    [
      "└─" <> sds.0 <> "┴─" <> sds.1 <> "┘"
    ],
  ]
  |> list.flatten
}

// **********************
// 4-column table printer
// **********************

pub fn four_column_maxes(
  lines: List(#(String, String, String, String))
) -> #(Int, Int, Int, Int) {
  list.fold(
    lines,
    #(0, 0, 0, 0),
    fn(acc, pair) {
      #(
        int.max(acc.0, string.length(pair.0)),
        int.max(acc.1, string.length(pair.1)),
        int.max(acc.2, string.length(pair.2)),
        int.max(acc.3, string.length(pair.3)),
      )
    }
  )
}

pub fn four_column_table(
  lines: List(#(String, String, String, String)),
) -> List(String) {
  let maxes = four_column_maxes(lines)
  let padding = #(1, 2, 1, 1)
  let one_line = fn(tuple: #(String, String, String, String), index: Int) -> String {
    "│ " <> tuple.0 <> spaces(maxes.0 - string.length(tuple.0) + padding.0) <>
    "│ " <> tuple.1 <> case index % 2 {
      1 -> dots(maxes.1 - string.length(tuple.1) + padding.1)
      _ if index >= 0 -> twodots(maxes.1 - string.length(tuple.1) + padding.1)
      _ -> spaces(maxes.1 - string.length(tuple.1) + padding.1)
    } <>
    "│ " <> tuple.2 <> spaces(maxes.2 - string.length(tuple.2) + padding.2) <>
    "│ " <> tuple.3 <> spaces(maxes.3 - string.length(tuple.3) + padding.3) <>
    "│"
  }
  let sds = #(
    solid_dashes(maxes.0 + padding.0),
    solid_dashes(maxes.1 + padding.1),
    solid_dashes(maxes.2 + padding.2),
    solid_dashes(maxes.3 + padding.3),
  )
  let assert [first, ..rest] = lines
  [
    [
      "┌─" <> sds.0 <> "┬─" <> sds.1 <> "┬─" <> sds.2 <> "┬─" <> sds.3 <> "┐",
      one_line(first, -1),
      "├─" <> sds.0 <> "┼─" <> sds.1 <> "┼─" <> sds.2 <> "┼─" <> sds.3 <> "┤"
    ],
    list.index_map(rest, one_line),
    [
      "└─" <> sds.0 <> "┴─" <> sds.1 <> "┴─" <> sds.2 <> "┴─" <> sds.3 <> "┘"
    ],
  ]
  |> list.flatten
}

pub fn print_lines_at_indent(
  lines: List(String),
  indent: Int,
) -> Nil {
  let margin = spaces(indent)
  list.each(lines, fn(l) {io.println(margin <> l)})
}

// ************************
// desugarer
// ************************

pub fn name_and_param_string(
  desugarer: Desugarer,
  step_no: Int,
) -> String {
  ins(step_no)
  <> ". "
  <> desugarer.name
  <> case desugarer.stringified_param {
    Some(desc) ->
      " "
      <> ins(desc)
      |> string.drop_start(1)
      |> string.drop_end(1)
      |> string.replace("\\\"", "\"")
    None -> ""
  }
}

pub fn turn_into_paragraph(
  message: String,
  max_line_length: Int,
) -> List(String) {
  let len = string.length(message)
  use <- on.true_false(
    len < max_line_length,
    on_true: [message],
  )
  let shortest = max_line_length * 3 / 5
  let #(current_start, current_end, remaining) = #(
    string.slice(message, 0, shortest),
    string.slice(message, shortest, max_line_length - shortest),
    string.slice(message, max_line_length, len),
  )
  case string.split_once(current_end |> string.reverse, " ") {
    Ok(#(before, after)) -> [
      current_start <> {after |> string.reverse},
      ..turn_into_paragraph(
        { before |> string.reverse } <> remaining,
        max_line_length
      )
    ]
    _ -> [
      current_start <> current_end,
      ..turn_into_paragraph(remaining, max_line_length)
    ]
  }
}

pub fn padded_error_paragraph(
  message: String,
  max_line_length: Int,
  pad: String,
) -> List(String) {
  message
  |> turn_into_paragraph(max_line_length)
  |> list.index_map(
    fn(s, i) {
      case i > 0 {
        False -> s
        True -> pad <> s
      }
    }
  )
}

pub fn strip_quotes(
  string: String,
) -> String {
  case {
    string.starts_with(string, "") &&
    string.ends_with(string, "") &&
    string != ""
  } {
    True -> string |> string.drop_start(1) |> string.drop_end(1)
    False -> string
  }
}

fn ddd_truncate(str: String, max_cols) -> String {
  case string.length(str) > max_cols {
    False -> str
    True -> {
      let excess = string.length(str) - max_cols
      string.drop_end(str, excess + 3) <> "..."
    }
  }
}

fn desugarer_to_list_lines(
  desugarer: Desugarer,
  index: Int,
  max_param_cols: Int,
  max_outside_cols: Int,
  none_string: String,
) -> List(#(String, String, String, String)) {
  let number = ins(index + 1) <> "."
  let name = desugarer.name
  let param_lines = case desugarer.stringified_param {
    None -> [none_string]
    Some(thing) ->
      case string.split(thing, "\n") {
        [] -> panic as "stringified param is empty string?"
        lines -> lines |> list.map(ddd_truncate(_, max_param_cols))
      }
  }
  let outside = case desugarer.stringified_outside {
    None -> none_string
    Some(thing) -> thing |> ddd_truncate(max_outside_cols)
  }
  list.index_map(param_lines, fn(p, i) {
    case i == 0 {
      True -> #(number, name, p, outside)
      False -> #("", spaces(string.length(name)), p, "⋮")
    }
  })
}

pub fn print_pipeline(desugarers: List(Desugarer)) {
  let none_string = "--"
  let max_param_cols = 65
  let max_outside_cols = 45

  let lines =
    desugarers
    |> list.index_map(fn(d, i) {
      desugarer_to_list_lines(
        d,
        i,
        max_param_cols,
        max_outside_cols,
        none_string,
      )
    })
    |> list.flatten

  io.println("• pipeline:")

  [#("#.", "name", "param", "outside"), ..lines]
  |> four_column_table
  |> print_lines_at_indent(2)
}

pub fn our_blame_digest(blame: Blame) -> String {
  case bl.blame_digest(blame) {
    "" -> "--"
    s -> s
  }
}

fn boxed_error_lines(
  lines: List(String),
  emoji: String,
) -> List(String) {
  let lengths = list.map(lines, string.length)
  let max = list.fold(lengths, 0, fn(acc, n) { int.max(acc, n) }) + 2
  let max = case max % 2 == 0 {
    True -> max
    False -> max + 1
  }
  [
    [
      string.repeat(emoji, 4 + max / 2),
      string.repeat(emoji, 4 + max / 2),
    ],
    list.map(
      list.zip(lines, lengths),
      fn (pair) {
        let #(line, line_length) = pair
        emoji <> emoji <> line <> spaces(max - line_length) <> emoji <> emoji
      }
    ),
    [
      string.repeat(emoji, 4 + max / 2),
      string.repeat(emoji, 4 + max / 2),
    ],
  ]
  |> list.flatten
}

pub fn boxed_error_announcer(
  lines: List(String),
  emoji: String,
  indent: Int,
  lines_before_after: #(Int, Int)
) -> Nil {
  let margin = spaces(indent)
  let lines =
    lines
    |> boxed_error_lines(emoji)
    |> list.map(fn(l){margin <> l})
    |> string.join("\n")
  io.print(string.repeat("\n", lines_before_after.0))
  io.println(lines)
  io.print(string.repeat("\n", lines_before_after.1))
}
