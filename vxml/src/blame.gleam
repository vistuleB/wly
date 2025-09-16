import gleam/int
import gleam/list
import gleam/string.{inspect as ins}

pub type Blame {
  Src(
    comments: List(String),
    path: String,
    line_no: Int,
    char_no: Int,
  )

  Des(
    comments: List(String),
    name: String,
    line_no: Int,
  )

  Ext(
    comments: List(String),
    name: String,
  )

  NoBlame(
    comments: List(String),
  )
}

// *************
// private utils
// *************

fn spaces(i: Int) -> String {
  string.repeat(" ", i)
}

// ******************************
// pub utility functions & consts
// ******************************

pub const no_blame = NoBlame([])

pub fn source_blame(
  path: String,
  line_no: Int,
  char_no: Int,
) -> Blame {
  Src([], path, line_no, char_no)
}

pub fn desugarer_blame(name: String, line_no: Int) -> Blame {
  Des([], name, line_no)
}

pub fn emitter_blame(name: String) -> Blame {
  Ext([], name)
}

pub fn clear_comments(blame: Blame) -> Blame {
  case blame {
    Src(_, _, _, _) -> Src(..blame, comments: [])
    Des(_, _, _) -> Des(..blame, comments: [])
    Ext(_, _) -> Ext(..blame, comments: [])
    NoBlame(_) -> NoBlame([])
  }
}

pub fn prepend_comment(blame: Blame, comment: String) -> Blame {
  case blame {
    Src(_, _, _, _) -> Src(..blame, comments: [comment, ..blame.comments])
    Des(_, _, _) -> Des(..blame, comments: [comment, ..blame.comments])
    Ext(_, _) -> Ext(..blame, comments: [comment, ..blame.comments])
    NoBlame(_) -> NoBlame(comments: [comment, ..blame.comments])
  }
}

pub fn append_comment(blame: Blame, comment: String) -> Blame {
  case blame {
    Src(_, _, _, _) -> Src(..blame, comments: list.append(blame.comments, [comment]))
    Des(_, _, _) -> Des(..blame, comments: list.append(blame.comments, [comment]))
    Ext(_, _) -> Ext(..blame, comments: list.append(blame.comments, [comment]))
    NoBlame(_) -> NoBlame(comments: list.append(blame.comments, [comment]))
  }  
}

pub fn advance(blame: Blame, by: Int) -> Blame {
  case blame {
    Src(_, _, _, _) -> Src(..blame, char_no: blame.char_no + by)
    _ -> blame
  }
}

pub fn blame_digest(blame: Blame) -> String {
  case blame {
    Src(_, path, line_no, char_no) -> path <> ":" <> ins(line_no) <> ":" <> ins(char_no)
    Des(_, name, line_no) -> name <> "♦" <> ins(line_no)
    Ext(_, name) -> "e:" <> name
    NoBlame(_) -> ""
  }
}

pub fn comments_digest(
  blame: Blame,
) -> String {
  list.index_fold(
    blame.comments,
    "[",
    fn(acc, comment, i) {
      acc <> case i > 0 {
        True -> ", "
        False -> ""
      }
      <> comment
    }
  )
  <> "]"
}

// **************************************************
// List(#(Blame, String)) pretty-printer (no1)
// **************************************************

fn truncate_with_suffix_or_pad(
  content: String,
  desired_length: Int,
  truncation_suffix: String,
) -> String {
  let l = string.length(content)
  case l > desired_length {
    True -> string.drop_end(content, l - {desired_length - string.length(truncation_suffix)}) <> truncation_suffix
    False -> content <> spaces(desired_length - l)
  }
}

fn mid_truncation_or_pad(
  content: String,
  desired_length: Int,
  mid_truncation_dots: String,
) -> String {
  let l = string.length(content)
  case l + 1 >= desired_length {
    True -> {
      let amt_to_drop = 1 + l - {desired_length - string.length(mid_truncation_dots)}
      let inner_content = string.drop_start(content, 2)
      let slice_start = { string.length(inner_content) / 2 } - {amt_to_drop / 2} - 3
      let start = string.slice(inner_content, 0, slice_start)
      let end = string.slice(inner_content, slice_start + amt_to_drop, 1000)
      "| " <> start <> mid_truncation_dots <> end <> " "
    }
    False -> content <> spaces(desired_length - l)
  }
}

fn glue_columns_3(
  table_lines: List(#(String, String, String)),
  min_max_col1: #(Int, Int),
  min_max_col2: #(Int, Int),
  mid_truncation_dots: String,
  truncation_suffix_col2: String,
) -> #(#(Int, Int), List(String)) {
  let #(col1_max, col2_max) = list.fold(
    table_lines,
    #(0, 0),
    fn (acc, tuple) {
      #(
        int.max(acc.0, tuple.0 |> string.length),
        int.max(acc.1, tuple.1 |> string.length),
      )
    }
  )

  let col1_size = int.max(int.min(col1_max, min_max_col1.1), min_max_col1.0)
  let col2_size = int.max(int.min(col2_max, min_max_col2.1), min_max_col2.0)

  let table_lines =
    list.map(
      table_lines,
      fn (tuple) {
        mid_truncation_or_pad(tuple.0, col1_size, mid_truncation_dots)
        <> truncate_with_suffix_or_pad(tuple.1, col2_size, truncation_suffix_col2)
        <> tuple.2
      }
    )

  #(#(col1_size, col2_size), table_lines)
}

fn blamed_strings_annotated_table_no1_header_lines(
  margin_total_width: Int,
  extra_dashes_for_content: Int,
) -> List(String) {
  [
    "┌" <> string.repeat("─", margin_total_width + extra_dashes_for_content),
    "│ Blame" <> string.repeat(" ", margin_total_width - 7) <> "█doc",
    "├" <> string.repeat("─", margin_total_width + extra_dashes_for_content),
  ]
}

fn blamed_strings_annotated_table_no1_body_lines(
  contents: List(#(Blame, String)),
  banner: String,
) -> #(#(Int, Int), List(String)) {
  let banner = case banner == "" {
    True -> ""
    False -> "(" <> banner <> ")"
  }

  let #(#(cols1, cols2), table_lines) =
    list.map(
      contents,
      fn(c) {#(
        "│ " <> banner <> blame_digest(c.0),
        comments_digest(c.0),
        "█" <> c.1,
      )},
    )
    |> glue_columns_3(#(48, 48), #(30, 30), "...", "...]")

  #(#(cols1, cols2), table_lines)
}

fn blamed_strings_annotated_table_no1_footer_lines(
  margin_total_width: Int,
  extra_dashes_for_content: Int,
) -> List(String) {
  [
    "└" <> string.repeat("─", margin_total_width + extra_dashes_for_content),
  ]
}

pub fn blamed_strings_annotated_table_no1(
  lines: List(#(Blame, String)),
  banner: String,
) -> List(String) {
  let #(#(cols1, cols2), body_lines) =
    blamed_strings_annotated_table_no1_body_lines(lines, banner)

  [
    blamed_strings_annotated_table_no1_header_lines(cols1 + cols2, 38),
    body_lines,
    blamed_strings_annotated_table_no1_footer_lines(cols1 + cols2, 38),
  ]
  |> list.flatten
}
