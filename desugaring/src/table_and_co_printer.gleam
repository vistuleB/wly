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
pub fn underscores(num: Int) -> String { string.repeat("_", num) }
pub fn blocks(num: Int) -> String { string.repeat("█", num) }

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
// 3-column table printer
// **********************

pub fn three_column_maxes(
  lines: List(#(String, String, String))
) -> #(Int, Int, Int) {
  list.fold(
    lines,
    #(0, 0, 0),
    fn(acc, triple) {
      #(
        int.max(acc.0, string.length(triple.0)),
        int.max(acc.1, string.length(triple.1)),
        int.max(acc.2, string.length(triple.2)),
      )
    }
  )
}

pub fn three_column_table(
  lines: List(#(String, String, String)),
) -> List(String) {
  let maxes = three_column_maxes(lines)
  let padding = #(1, 2, 1)
  let total_width = maxes.0 + maxes.1 + maxes.2 + padding.0 + padding.1 + padding.2 + 7
  let one_line = fn(cols: #(String, String, String)) -> String {
    case string.starts_with(cols.1, "table_marker") {
      True -> {
        let block = "er%%%%%%%%%%%%%%%%%dl.table_mark"
        // let block = "████dl.tmable_marker█████████"
        let block_length = block |> string.length
        let num_blocks = { total_width + block_length - 1 } / block_length
        block
        |> string.repeat(num_blocks)
        |> string.drop_end(num_blocks * block_length - total_width)
      }
      False -> {
        "│ " <> cols.0 <> spaces(maxes.0 - string.length(cols.0) + padding.0) <>
        "│ " <> cols.1 <> spaces(maxes.1 - string.length(cols.1) + padding.1) <>
        "│ " <> cols.2 <> spaces(maxes.2 - string.length(cols.2) + padding.2) <>
        "│"
      }
    }
  }
  let sds = #(
    solid_dashes(maxes.0 + padding.0),
    solid_dashes(maxes.1 + padding.1),
    solid_dashes(maxes.2 + padding.2),
  )
  let assert [first, ..rest] = lines
  [
    [
      "┌─" <> sds.0 <> "┬─" <> sds.1 <> "┬─" <> sds.2 <> "┐",
      one_line(first),
      "├─" <> sds.0 <> "┼─" <> sds.1 <> "┼─" <> sds.2 <> "┤"
    ],
    list.map(rest, one_line),
    [
      "└─" <> sds.0 <> "┴─" <> sds.1 <> "┴─" <> sds.2 <> "┘"
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
  let total_width = 9 + maxes.0 + padding.0 + maxes.1 + padding.1 + maxes.2 + padding.2 + maxes.3 + padding.3
  let one_line = fn(tuple: #(String, String, String, String), index: Int) -> String {
    case string.starts_with(tuple.1, "table_marker") {
      True -> {
        let block = "er%%%%%%%%%%%%%%%%%dl.table_mark"
        let block_length = block |> string.length
        let num_blocks = { total_width + block_length - 1 } / block_length
        block
        |> string.repeat(num_blocks)
        |> string.drop_end(num_blocks * block_length - total_width)
      }
      False -> {
        "│ " <> tuple.0 <> spaces(maxes.0 - string.length(tuple.0) + padding.0) <>
        "│ " <> tuple.1 <> case index % 2 {
          1 -> dots(maxes.1 - string.length(tuple.1) + padding.1)
          _ if index >= 0 -> underscores(maxes.1 - string.length(tuple.1) + padding.1)
          _ -> spaces(maxes.1 - string.length(tuple.1) + padding.1)
        } <>
        "│ " <> tuple.2 <> spaces(maxes.2 - string.length(tuple.2) + padding.2) <>
        "│ " <> tuple.3 <> spaces(maxes.3 - string.length(tuple.3) + padding.3) <>
        "│"
      }
    }
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

pub fn name_and_param_string_lines(
  desugarer: Desugarer,
  step_no: Int,
  margin: Int,
) -> List(String) {
  let #(first_line, batch_params) = {
    let start =
      ins(step_no)
      <> ". "
      <> desugarer.name
    let #(end, more) = {
      case desugarer.stringified_param {
        None -> #(
          case desugarer.stringified_outside {
            None -> ""
            _ -> " []"
          },
          [],
        )
        Some(desc) -> case string.split(desc, "\n") {
          [desc] -> {
            let end =
              " " <> {
                ins(desc)
                |> string.drop_start(1)
                |> string.drop_end(1)
                |> string.replace("\\\"", "\"")
              }
            #(end, [])
          }
          [first, ..rest] -> {
            // assert string.starts_with(first, "[ ")
            let first = string.drop_start(first, 2)
            let assert [last, ..rest] = [first, ..rest] |> list.reverse
            case string.ends_with(last, "]") {
              True -> Nil
              False -> {
                io.println("bad stringified param at step_no: " <> ins(step_no))
                io.println(desugarer.stringified_param |> option.unwrap("None") <> "[end]")
                io.println(desugarer.stringified_outside |> option.unwrap("None") <> "[end]")
                panic
              }
            }
            let last = string.drop_end(last, 2)
            let more = [last, ..rest] |> list.reverse
            #(" [", more)
          }
          _ -> panic as "not expecting the non-None stringified_param to be the empty string"
        }
      }
    }
    #(start <> end, more)
  }

  let so_far =
    case batch_params {
      [] -> [first_line]
      _ -> {
        [
          [first_line],
          list.index_map(
            batch_params,
            fn (b, i) { "  " <> string.drop_start(b, case i > 0 {
              True -> 2
              False -> 0
            }) <> "," },
          ),
          ["]"]
        ]
        |> list.flatten
      }
    }

  let spaces = spaces(margin)

  case desugarer.stringified_outside {
    None -> so_far
    Some(x) -> {
      let assert [last, ..rest] = list.reverse(so_far)
      [last <> " " <> x, ..rest] |> list.reverse
    }
  }
  |> list.map(fn(l) { spaces <> l })
}

pub fn turn_into_paragraph(
  message: String,
  max_line_length: Int,
) -> List(String) {
  let len = string.length(message)
  use <- on.true_false(
    len < max_line_length,
    on_true: fn() { [message] },
  )
  let shortest = max_line_length * 3 / 5
  let #(current_start, current_end, remaining) = #(
    string.slice(message, 0, shortest),
    string.slice(message, shortest, max_line_length - shortest),
    string.slice(message, max_line_length, len),
  )
  case string.split_once(current_end |> string.reverse, " ") {
    Ok(#(before, after)) -> [
      current_start <> { after |> string.reverse },
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

fn dash_banner(
  title: String,
  width: Int,
) -> String {
  let side = { width - string.length(title) } / 2
  let s1 = string.repeat("-", side)
  let s2 = string.repeat("-", width - string.length(title) - side)
  s1 <> title <> s2
}

pub fn two_column_error_announcer(
  announces: List(#(String, String)),
  col1_min: Int,
  col2_min: Int,
  emoji: String,
  margin: Int,
  banner: String,
) -> String {
  let #(col1_max, _col2_max) = two_column_maxes(announces)
  let col1 = int.max(col1_min, col1_max + 1)
  let firsts = list.map(
    announces,
    fn (pair) { string.pad_end(pair.0, col1, " ") },
  )
  let #(max, seconds) = list.map_fold(
    announces,
    0,
    fn (acc, pair) {
      let lines = turn_into_paragraph(pair.1, col2_min)
      let assert Ok(max) = list.map(lines, string.length) |> list.max(int.compare)
      #(int.max(max, acc), lines)
    }
  )
  let col2 = int.max(max + 1, col2_min + 1)
  let spaces = string.repeat(" ", margin)
  let emojis = string.repeat(emoji, 2)
  let t = margin + 2 + col1 + col2
  let dashes1 = dash_banner(banner, col1 + col2 - 2)
  let dashes2 = string.repeat("-", col1 + col2 - 2)
  let opening_line = spaces <> emojis <> " " <> dashes1 <> " " <> emojis
  let closing_line = spaces <> emojis <> " " <> dashes2 <> " " <> emojis
  let other_spaces = string.repeat(" ", col1)
  let q =
    list.map2(
      firsts,
      seconds,
      fn(f, s) {
        let assert [s0, ..rest] = s
        let l0 = string.pad_end(spaces <> emojis <> f <> s0, t, " ") <> emojis
        let rest = list.map(
          rest,
          fn(r) {
            spaces <> emojis <> other_spaces <> string.pad_end(r, col2, " ") <> emojis
          }
        )
        [l0, ..rest]
      }
    )
    |> list.flatten
  [opening_line, ..q] |> list.append([closing_line])
  |> string.join("\n")
}