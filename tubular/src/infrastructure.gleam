import gleam/float
import gleam/int
import blame.{type Blame} as bl
import io_lines.{type OutputLine, OutputLine} as io_l
import gleam/dict.{type Dict}
import gleam/io
import gleam/list
import gleam/pair
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string.{inspect as ins}
import vxml.{type Attribute, Attribute, type TextLine, type VXML, TextLine, T, V, vxml_to_string}
import on

// ************************************************************
// Traffic Light for early returns
// ************************************************************

pub type TrafficLight {
  Continue
  GoBack
}

// ************************************************************
// css-unit parsing
// ************************************************************

pub type CSSUnit {
  PX
  REM
  EM
}

pub fn parse_to_float(s: String) -> Result(Float, Nil) {
  case float.parse(s), int.parse(s) {
    Ok(number), _ -> Ok(number)
    _, Ok(number) -> Ok(int.to_float(number))
    _, _ -> Error(Nil)
  }
}

fn extract_css_unit(s: String) -> #(String, Option(CSSUnit)) {
  use <- on.true_false(
    string.ends_with(s, "rem"),
    #(string.drop_end(s, 3), Some(REM)),
  )

  use <- on.true_false(
    string.ends_with(s, "em"),
    #(string.drop_end(s, 2), Some(EM)),
  )

  use <- on.true_false(
    string.ends_with(s, "px"),
    #(string.drop_end(s, 2), Some(PX)),
  )

  #(s, None)
}

pub fn parse_number_and_optional_css_unit(
  s: String
) -> Result(#(Float, Option(CSSUnit)), Nil) {
  let #(before_unit, unit) = extract_css_unit(s)
  use number <- result.try(parse_to_float(before_unit))
  Ok(#(number, unit))
}

// ************************************************************
// LatexDelimiterPair, LatexDelimiterSingleton
// ************************************************************

pub type LatexDelimiterPair {
  DoubleDollar
  SingleDollar
  BackslashParenthesis
  BackslashSquareBracket
  BeginEndAlign
  BeginEndAlignStar
}

pub type LatexDelimiterSingleton {
  DoubleDollarSingleton
  SingleDollarSingleton
  BackslashOpeningParenthesis
  BackslashClosingParenthesis
  BackslashOpeningSquareBracket
  BackslashClosingSquareBracket
  BeginAlign
  EndAlign
  BeginAlignStar
  EndAlignStar
}

pub fn latex_inline_delimiters(
) -> List(LatexDelimiterPair) {
  [SingleDollar, BackslashParenthesis]
}

pub fn latex_strippable_display_delimiters(
) -> List(LatexDelimiterPair) {
  [DoubleDollar, BackslashSquareBracket]
}

pub fn latex_strippable_delimiter_pairs(
) -> List(LatexDelimiterPair) {
  [DoubleDollar, SingleDollar, BackslashParenthesis, BackslashSquareBracket]
}

pub fn opening_and_closing_string_for_pair(
  pair: LatexDelimiterPair
) -> #(String, String) {
  case pair {
    DoubleDollar -> #("$$", "$$")
    SingleDollar -> #("$", "$")
    BackslashParenthesis -> #("\\(", "\\)")
    BackslashSquareBracket -> #("\\[", "\\]")
    BeginEndAlign -> #("\\begin{align}", "\\end{align}")
    BeginEndAlignStar -> #("\\begin{align*}", "\\end{align*}")
  }
}

pub fn opening_and_closing_singletons_for_pair(
  pair: LatexDelimiterPair
) -> #(LatexDelimiterSingleton, LatexDelimiterSingleton) {
  case pair {
    DoubleDollar -> #(DoubleDollarSingleton, DoubleDollarSingleton)
    SingleDollar -> #(SingleDollarSingleton, SingleDollarSingleton)
    BackslashParenthesis -> #(BackslashOpeningParenthesis, BackslashClosingParenthesis)
    BackslashSquareBracket -> #(BackslashOpeningSquareBracket, BackslashClosingSquareBracket)
    BeginEndAlign -> #(BeginAlign, EndAlign)
    BeginEndAlignStar -> #(BeginAlignStar, EndAlignStar)
  }
}

pub fn left_right_delim_strings(delimiters: List(LatexDelimiterPair)) -> #(List(String), List(String)) {
  delimiters
  |> list.map(opening_and_closing_string_for_pair)
  |> list.unzip
}

// ************************************************************
// use <- utilities
// ************************************************************

pub fn on_v_on_t(
  node: VXML,
  f1: fn(Blame, String, List(Attribute), List(VXML)) -> c,
  f2: fn(Blame, List(TextLine)) -> c,
) -> c {
  case node {
    V(blame, tag, attributes, children) -> f1(blame, tag, attributes, children)
    T(blame, lines) -> f2(blame, lines)
  }
}

pub fn on_t_on_v(
  node: VXML,
  f1: fn(Blame, List(TextLine)) -> c,
  f2: fn(Blame, String, List(Attribute), List(VXML)) -> c,
) -> c {
  case node {
    T(blame, lines) -> f1(blame, lines)
    V(blame, tag, attributes, children) -> f2(blame, tag, attributes, children)
  }
}

// ************************************************************
// get_root
// ************************************************************

pub fn get_root(vxmls: List(VXML)) -> Result(VXML, String) {
  case vxmls {
    [] -> Error("vxml is empty!")
    [root] -> Ok(root)
    _ -> Error("found " <> ins(list.length(vxmls)) <> " > 1 top-level nodes")
  }
}

pub fn get_root_with_desugaring_error(vxmls: List(VXML)) -> Result(VXML, DesugaringError) {
  get_root(vxmls)
  |> result.map_error(fn(msg) { DesugaringError(bl.no_blame, msg)})
}

// ************************************************************
// descendant_ text_contains/!text_contains
// ************************************************************

pub fn descendant_text_contains(
  v: VXML,
  s: String,
) -> Bool {
  case v {
    T(_, lines) -> lines_contain(lines, s)
    V(_, _, _, children) -> list.any(children, descendant_text_contains(_, s))
  }
}

pub fn descendant_text_does_not_contain(
  vxml: VXML,
  s: String,
) -> Bool {
  !descendant_text_contains(vxml, s)
}

pub fn filter_descendants(vxml: VXML, condition: fn(VXML) -> Bool) -> List(VXML) {
  case vxml {
    T(_, _) -> []
    V(_, _, _, children) -> {
      let matching_children = list.filter(children, condition)
      let descendants_from_children =
        list.map(children, filter_descendants(_, condition))
        |> list.flatten

      list.flatten([
        matching_children,
        descendants_from_children,
      ])
    }
  }
}

pub fn descendants_with_tag(vxml: VXML, tag: String) -> List(VXML) {
  filter_descendants(vxml, is_v_and_tag_equals(_, tag))
}

pub fn descendants_with_key_value(vxml: VXML, attr_key: String, attr_value: String) -> List(VXML) {
  filter_descendants(vxml, is_v_and_has_key_value(_, attr_key, attr_value))
}

pub fn descendants_with_class(vxml: VXML, class: String) -> List(VXML) {
  filter_descendants(vxml, has_class(_, class))
}

// ************************************************************
// list utilities
// ************************************************************

pub fn get_duplicate(list: List(a)) -> Option(a) {
  case list {
    [] -> None
    [first, ..rest] ->
      case list.contains(rest, first) {
        True -> Some(first)
        False -> get_duplicate(rest)
      }
  }
}

pub fn get_contained(from: List(a), in: List(a)) -> Option(a) {
  case from {
    [] -> None
    [first, ..rest] -> case list.contains(in, first) {
      True -> Some(first)
      False -> get_contained(rest, in)
    }
  }
}

/// dumps the contents of 'from' "upside-down" into
/// 'into', so that the first element of 'from' ends
/// up buried inside the resulting list, while the last
/// element of 'from' ends up surfaced as the first
/// element of the result
pub fn pour(from: List(a), into: List(a)) -> List(a) {
  case from {
    [first, ..rest] -> pour(rest, [first, ..into])
    [] -> into
  }
}

pub fn index_map_fold(
  list: List(a),
  initial_acc: b,
  f: fn(b, a, Int) -> #(b, c),
) -> #(b, List(c)) {
  list.index_fold(list, #(initial_acc, []), fn(acc, item, index) {
    let #(current_acc, results) = acc
    let #(new_acc, result) = f(current_acc, item, index)
    #(new_acc, [result, ..results])
  })
  |> pair.map_second(list.reverse)
}

pub fn try_map_fold(
  over ze_list: List(q),
  from state: a,
  with f: fn(a, q) -> Result(#(q, a), c)
) -> Result(#(List(q), a), c) {
  case ze_list {
    [] -> Ok(#([], state))
    [first, ..rest] -> {
      use #(mapped_first, state) <- result.try(f(state, first))
      use #(mapped_rest, state) <- result.try(try_map_fold(rest, state, f))
      Ok(#([mapped_first, ..mapped_rest], state))
    }
  }
}

pub fn list_set(ze_list: List(a), index: Int, element: a) -> List(a) {
  let assert True = 0 <= index && index <= list.length(ze_list)
  let prefix = list.take(ze_list, index)
  let suffix = list.drop(ze_list, index + 1)
  [
    prefix,
    [element],
    suffix,
  ]
  |> list.flatten
}

pub fn get_at(ze_list: List(a), index: Int) -> Result(a, Nil) {
  case index >= list.length(ze_list) || index < 0 {
    True -> Error(Nil)
    False -> list.drop(ze_list, index) |> list.first
  }
}

pub fn list_param_stringifier(param: List(p)) -> String {
  "[" <> {
    param
    |> list.index_map(
      fn(p, i) {
        case i > 0 {
          True -> ", " <> ins(p)
          False -> " " <> ins(p)
        }
      }
    )
    |> string.join("\n")
  }
  <> " ]"
}

pub fn drop_last(z: List(a)) -> List(a) {
  z |> list.reverse |> list.drop(1) |> list.reverse
}

fn index_of_internal(ze_list: List(a), thing: a, current_index: Int) -> Int {
  case ze_list {
    [] -> -1
    [first, ..] if first == thing -> current_index
    [_, ..rest] -> index_of_internal(rest, thing, current_index + 1)
  }
}

pub fn index_of(ze_list: List(a), thing: a) -> Int {
  index_of_internal(ze_list, thing, 0)
}

pub type SingletonError {
  MoreThanOne
  LessThanOne
}

pub fn read_singleton(z: List(a)) -> Result(a, SingletonError) {
  case z {
    [] -> Error(LessThanOne)
    [one] -> Ok(one)
    _ -> Error(MoreThanOne)
  }
}

pub fn append_if_not_present(ze_list: List(a), ze_thing: a) -> List(a) {
  case list.contains(ze_list, ze_thing) {
    True -> ze_list
    False -> list.append(ze_list, [ze_thing])
  }
}

// ************************************************************
// tuples
// ************************************************************

pub fn quad_to_pair_pair(
  t: #(a, b, c, d)
) -> #(#(a, b), #(c, d)) {
  #(#(t.0, t.1), #(t.2, t.3))
}

pub fn quad_drop_3rd(t: #(a, b, c, d)) -> #(a, b, d) {
  #(t.0, t.1, t.3)
}

pub fn quad_drop_4th(t: #(a, b, c, d)) -> #(a, b, c) {
  #(t.0, t.1, t.2)
}

pub fn triple_3rd(t: #(a, b, c)) -> c {
  t.2
}

pub fn triple_drop_2nd(t: #(a, b, c)) -> #(a, c) {
  #(t.0, t.2)
}

pub fn triple_drop_3rd(t: #(a, b, c)) -> #(a, b) {
  #(t.0, t.1)
}

pub fn triple_to_pair(t: #(a, b, c)) -> #(a, #(b, c)) {
  #(t.0, #(t.1, t.2))
}

pub fn quad_to_pair(t: #(a, b, c, d)) -> #(a, #(b, c, d)) {
  #(t.0, #(t.1, t.2, t.3))
}

pub fn quads_to_pair_pairs(
  l: List(#(a, b, c, d)),
) -> List(#(#(a, b), #(c, d))) {
  l
  |> list.map(quad_to_pair_pair)
}

pub fn triples_to_pairs(l: List(#(a, b, c))) -> List(#(a, #(b, c))) {
  l
  |> list.map(triple_to_pair)
}

pub fn quads_to_pairs(l: List(#(a, b, c, d))) -> List(#(a, #(b, c, d))) {
  l
  |> list.map(quad_to_pair)
}

//**************************************************************
//* dictionary-building utilities
//**************************************************************

pub fn validate_unique_keys(
  l: List(#(a, b))
) -> Result(List(#(a, b)), DesugaringError) {
  case get_duplicate(list.map(l, pair.first)) {
    Some(guy) -> Error(DesugaringError(bl.no_blame, "duplicate key in list being converted to dict: " <> ins(guy)))
    None -> Ok(l)
  }
}

pub fn dict_from_list_with_desugaring_error(
  l: List(#(a, b))
) -> Result(Dict(a, b), DesugaringError) {
  validate_unique_keys(l)
  |> result.map(dict.from_list(_))
}

pub fn aggregate_on_first(l: List(#(a, b))) -> Dict(a, List(b)) {
  list.fold(l, dict.from_list([]), fn(d, pair) {
    let #(a, b) = pair
    case dict.get(d, a) {
      Error(Nil) -> dict.insert(d, a, [b])
      Ok(prev_list) -> dict.insert(d, a, [b, ..prev_list])
    }
  })
}

pub fn use_list_pair_as_dict(
  list_pairs: List(#(a, b)),
  key: a,
) -> Result(b, Nil) {
  case list_pairs {
    [] -> Error(Nil)
    [#(alice, bob), ..] if alice == key -> Ok(bob)
    [_, ..rest] -> use_list_pair_as_dict(rest, key)
  }
}

pub fn triples_to_dict(l: List(#(a, b, c))) -> Dict(a, #(b, c)) {
  l
  |> triples_to_pairs
  |> dict.from_list
}

pub fn triples_to_aggregated_dict(l: List(#(a, b, c))) -> Dict(a, List(#(b, c))) {
  l
  |> triples_to_pairs
  |> aggregate_on_first
}

//**************************************************************
//* EitherOr
//**************************************************************

pub type EitherOr(a, b) {
  Either(a)
  Or(b)
}

fn regroup_eithers_accumulator(
  already_packaged: List(EitherOr(List(a), b)),
  under_construction: List(a),
  upcoming: List(EitherOr(a, b)),
) -> List(EitherOr(List(a), b)) {
  case upcoming {
    [] ->
      [under_construction |> list.reverse |> Either, ..already_packaged]
      |> list.reverse
    [Either(a), ..rest] ->
      regroup_eithers_accumulator(
        already_packaged,
        [a, ..under_construction],
        rest,
      )
    [Or(b), ..rest] ->
      regroup_eithers_accumulator(
        [
          Or(b),
          under_construction |> list.reverse |> Either,
          ..already_packaged
        ],
        [],
        rest,
      )
  }
}

fn regroup_ors_accumulator(
  already_packaged: List(EitherOr(a, List(b))),
  under_construction: List(b),
  upcoming: List(EitherOr(a, b)),
) -> List(EitherOr(a, List(b))) {
  case upcoming {
    [] ->
      [under_construction |> list.reverse |> Or, ..already_packaged]
      |> list.reverse
    [Or(b), ..rest] ->
      regroup_ors_accumulator(already_packaged, [b, ..under_construction], rest)
    [Either(a), ..rest] ->
      regroup_ors_accumulator(
        [
          Either(a),
          under_construction |> list.reverse |> Or,
          ..already_packaged
        ],
        [],
        rest,
      )
  }
}

pub fn remove_ors_unwrap_eithers(ze_list: List(EitherOr(a, b))) -> List(a) {
  list.filter_map(ze_list, fn(either_or) {
    case either_or {
      Either(sth) -> Ok(sth)
      Or(_) -> Error(Nil)
    }
  })
}

pub fn remove_eithers_unwrap_ors(ze_list: List(EitherOr(a, b))) -> List(b) {
  list.filter_map(ze_list, fn(either_or) {
    case either_or {
      Either(_) -> Error(Nil)
      Or(sth) -> Ok(sth)
    }
  })
}

pub fn regroup_eithers(
  ze_list: List(EitherOr(a, b)),
) -> List(EitherOr(List(a), b)) {
  regroup_eithers_accumulator([], [], ze_list)
}

pub fn regroup_ors(ze_list: List(EitherOr(a, b))) -> List(EitherOr(a, List(b))) {
  regroup_ors_accumulator([], [], ze_list)
}

pub fn regroup_eithers_no_empty_lists(
  ze_list: List(EitherOr(a, b)),
) -> List(EitherOr(List(a), b)) {
  regroup_eithers(ze_list)
  |> list.filter(fn(thing) {
    case thing {
      Either(a_list) -> !{ list.is_empty(a_list) }
      Or(_) -> True
    }
  })
}

pub fn regroup_ors_no_empty_lists(
  ze_list: List(EitherOr(a, b)),
) -> List(EitherOr(a, List(b))) {
  regroup_ors(ze_list)
  |> list.filter(fn(thing) {
    case thing {
      Either(_) -> True
      Or(a_list) -> !{ list.is_empty(a_list) }
    }
  })
}

pub fn on_either_on_or(t: EitherOr(a, b), fn1: fn(a) -> c, fn2: fn(b) -> c) -> c {
  case t {
    Either(a) -> fn1(a)
    Or(b) -> fn2(b)
  }
}

pub fn map_ors(
  ze_list: List(EitherOr(a, b)),
  f: fn(b) -> c,
) -> List(EitherOr(a, c)) {
  ze_list
  |> list.map(fn(thing) {
    case thing {
      Either(load) -> Either(load)
      Or(b) -> Or(f(b))
    }
  })
}

pub fn map_either_ors(
  ze_list: List(EitherOr(a, b)),
  fn1: fn(a) -> c,
  fn2: fn(b) -> c,
) -> List(c) {
  ze_list
  |> list.map(on_either_on_or(_, fn1, fn2))
}

pub fn either_or_misceginator(
  list: List(a),
  condition: fn(a) -> Bool,
) -> List(EitherOr(a, a)) {
  list.map(list, fn(thing) {
    case condition(thing) {
      True -> Either(thing)
      False -> Or(thing)
    }
  })
}

//**************************************************************
//* find replace
//**************************************************************

fn find_replace_in_line(
  line: TextLine,
  from: String,
  to: String,
) -> TextLine {
  TextLine(line.blame, string.replace(line.content, from, to))
}

pub fn t_find_replace(
  node: VXML,
  from: String,
  to: String,
) -> VXML {
  let assert T(blame, contents) = node
  T(
    blame,
    list.map(contents, find_replace_in_line(_, from, to))
  )
}

pub fn find_replace_if_t(
  node: VXML,
  from: String,
  to: String,
) -> VXML {
  case node {
    T(_, _) -> t_find_replace(node, from, to)
    _ -> node
  }
}

fn find_replace_in_line__batch(
  line: TextLine,
  pairs: List(#(String, String)),
) -> TextLine {
  list.fold(
    pairs,
    line,
    fn(acc, pair) { find_replace_in_line(acc, pair.0, pair.1) }
  )
}

pub fn t_find_replace__batch(t: VXML, pairs: List(#(String, String))) {
  let assert T(blame, lines) = t
  T(
    blame,
    lines
    |> list.map(find_replace_in_line__batch(_, pairs)),
  )
}

pub fn find_replace_if_t__batch(
  node: VXML,
  pairs: List(#(String, String)),
) -> VXML {
  case node {
    T(_, _) -> t_find_replace__batch(node, pairs)
    _ -> node
  }
}

// ************************************************************
// Blame
// ************************************************************

pub fn assert_get_first_blame(vxmls: List(VXML)) -> Blame {
  let assert [first, ..] = vxmls
  first.blame
}

// ************************************************************
// String
// ************************************************************

pub fn drop_starting_slash(path: String) -> String {
  case string.starts_with(path, "/") {
    True -> string.drop_start(path, 1)
    False -> path
  }
}

pub fn drop_ending_slash(path: String) -> String {
  case string.ends_with(path, "/") {
    True -> string.drop_end(path, 1)
    False -> path
  }
}

pub fn kabob_case_to_camel_case(input: String) -> String {
  input
  |> string.split("-")
  |> list.index_map(fn(word, index) {
    case index {
      0 -> word
      _ -> case string.to_graphemes(word) {
        [] -> ""
        [first, ..rest] -> string.uppercase(first) <> string.join(rest, "")
      }
    }
  })
  |> string.join("")
}

pub fn normalize_spaces(
  s: String
) -> String {
  s
  |> string.split(" ")
  |> list.filter(fn(x) { !string.is_empty(x) })
  |> string.join(" ")
}

pub fn extract_trim_start(content: String) -> #(String, String) {
  let new_content = string.trim_start(content)
  let num_spaces = string.length(content) - string.length(new_content)
  #(string.repeat(" ", num_spaces), new_content)
}

pub fn extract_trim_end(content: String) -> #(String, String) {
  let new_content = string.trim_end(content)
  let num_spaces = string.length(content) - string.length(new_content)
  #(string.repeat(" ", num_spaces), new_content)
}

// ************************************************************
// lines
// ************************************************************

pub fn lines_map_content(
  lines: List(TextLine),
  m: fn(String) -> String
) {
  lines |> list.map(fn(l) {TextLine(l.blame, m(l.content))})
}

pub fn lines_are_whitespace(
  lines: List(TextLine)
) -> Bool {
  list.all(
    lines,
    fn(line) { string.trim(line.content) == "" }
  )
}

pub fn lines_remove_starting_empty_lines(l: List(TextLine)) -> List(TextLine) {
  case l {
    [] -> []
    [first, ..rest] ->
      case first.content {
        "" -> lines_remove_starting_empty_lines(rest)
        _ -> l
      }
  }
}

pub fn lines_contain(
  lines: List(TextLine),
  s: String,
) -> Bool {
  list.any(lines, fn(line) { string.contains(line.content, s) })
}

pub fn lines_first_blame(lines: List(TextLine)) -> Blame {
  case lines {
    [] -> bl.no_blame
    [first, ..] -> first.blame
  }
}

pub fn echo_lines(
  lines: List(TextLine),
  announcer: String,
) -> List(TextLine) {
  let table =
    lines
    |> list.map(fn(line) { #(line.blame, "\"" <> line.content <> "\"") })
    |> bl.blamed_strings_annotated_table_no1("")
    |> list.map(fn(l) { "   " <> l })
    |> string.join("\n")
  io.println(announcer <> ":\n")
  io.println(table)
  lines
}

fn split_lines_internal(
  previous_splits: List(List(TextLine)),
  current_lines: List(TextLine),
  remaining: List(TextLine),
  splitter: String,
) -> List(List(TextLine)) {
  case remaining {
    [] -> [
      current_lines |> list.reverse,
      ..previous_splits
    ] |> list.reverse
    [first, ..rest] -> {
      case string.split_once(first.content, splitter) {
        Error(_) -> split_lines_internal(
          previous_splits,
          [first, ..current_lines],
          rest,
          splitter,
        )
        Ok(#(before, after)) -> split_lines_internal(
          [
            [
              TextLine(first.blame, before),
              ..current_lines
            ] |> list.reverse,
            ..previous_splits,
          ],
          [],
          [
            TextLine(first.blame, after),
            ..rest,
          ],
          splitter,
        )
      }
    }
  }
}

pub fn split_lines(
  lines: List(TextLine),
  splitter: String,
) -> List(List(TextLine)) {
  split_lines_internal(
    [],
    [],
    lines,
    splitter,
  )
}

pub fn trim_starting_spaces_except_first_line(vxml: VXML) {
  let assert T(blame, lines) = vxml
  let assert [first_line, ..rest] = lines
  let updated_rest =
    rest
    |> list.map(fn(line) {
      TextLine(..line, content: string.trim_start(line.content))
    })

  T(blame, [first_line, ..updated_rest])
}

pub fn trim_ending_spaces_except_last_line(vxml: VXML) {
  let assert T(blame, lines) = vxml
  let assert [last_line, ..rest] = lines |> list.reverse()
  let updated_rest =
    rest
    |> list.map(fn(line) {
      TextLine(..line, content: string.trim_end(line.content))
    })
  T(blame, list.reverse([last_line, ..updated_rest]))
}

pub fn lines_trim_start(
  lines: List(TextLine),
) -> List(TextLine) {
  case lines {
    [] -> []
    [first, ..rest] -> {
      case string.first(first.content) {
        Error(_) -> lines_trim_start(rest)
        Ok(" ") -> case string.trim_start(first.content) {
          "" -> lines_trim_start(rest)
          nonempty -> [TextLine(first.blame, nonempty), ..rest]
        }
        _ -> lines
      }
    }
  }
}

pub fn reversed_lines_trim_end(
  lines: List(TextLine),
) -> List(TextLine) {
  case lines {
    [] -> []
    [first, ..rest] -> {
      case string.last(first.content) {
        Error(_) -> reversed_lines_trim_end(rest)
        Ok(" ") -> case string.trim_end(first.content) {
          "" -> reversed_lines_trim_end(rest)
          nonempty -> reversed_lines_trim_end([TextLine(first.blame, nonempty), ..rest])
        }
        _ -> lines
      }
    }
  }
}

pub fn first_line_starts_with(
  lines: List(TextLine),
  s: String,
) -> Bool {
  case lines {
    [] -> False
    [TextLine(_, line), ..] -> string.starts_with(line, s)
  }
}

pub fn first_line_ends_with(
  lines: List(TextLine),
  s: String,
) -> Bool {
  case lines {
    [] -> False
    [TextLine(_, line), ..] -> string.ends_with(line, s)
  }
}

pub fn lines_total_chars(
  lines: List(TextLine)
) -> Int {
  lines
  |> list.map(fn(line) { string.length(line.content) })
  |> int.sum
}

// ************************************************************
// line wrapping
// ************************************************************

pub fn line_wrap_rearrangement_internal(
  is_very_first_token: Bool,
  _next_token_marks_beginning_of_line: Bool,
  current_blame: Blame,
  already_bundled: List(TextLine),
  tokens_4_current_line: List(String),
  wrap_beyond: Int,
  chars_left: Int,
  remaining_tokens: List(EitherOr(String, Blame)),
) -> #(List(TextLine), Int) {
  let bundle_current = fn() {
    TextLine(current_blame, tokens_4_current_line |> list.reverse |> string.join(" "))
  }
  case remaining_tokens {
    [] -> {
      let last = bundle_current()
      #(
        [last, ..already_bundled] |> list.reverse,
        last.content |> string.length,
      )
    }
    [Or(current_blame), ..rest] -> line_wrap_rearrangement_internal(
      False,
      True,
      current_blame,
      already_bundled,
      tokens_4_current_line,
      wrap_beyond,
      chars_left,
      rest,
    )
    [Either(next_token), ..rest] -> {
      let length = string.length(next_token)
      let new_chars_left = chars_left - length - 1
      let current_blame = bl.advance(current_blame, length + 1)
      case next_token == "" || chars_left > 0 || is_very_first_token {
        True -> line_wrap_rearrangement_internal(
          False,
          False,
          current_blame,
          already_bundled,
          [next_token, ..tokens_4_current_line],
          wrap_beyond,
          new_chars_left,
          rest,
        )
        False -> line_wrap_rearrangement_internal(
          False,
          False,
          current_blame,
          [bundle_current(), ..already_bundled],
          [next_token],
          wrap_beyond,
          wrap_beyond - length,
          rest,
        )
      }
    }
  }
}

pub fn line_wrap_rearrangement(
  lines: List(TextLine),
  starting_offset: Int,
  wrap_beyond: Int,
) -> #(List(TextLine), Int) {
  // 🚨
  // right now there is no option to protect empty first line
  // or to protect empty last line; these will be sucked in & create leading and
  // trailing spaces instead on the next & previous lines respectively;
  // we apparently don't need this protection functionality, so far
  // 🚨
  let tokens =
    lines
    |> list.map(
      fn(line) {
        string.split(line.content, " ")
        |> list.map(Either)
        |> list.prepend(Or(line.blame))
      }
    )
    |> list.flatten
  let assert [Or(first_blame), ..tokens] = tokens
  let #(lines, last_line_length) = line_wrap_rearrangement_internal(
    True,
    True,
    first_blame,
    [],
    [],
    wrap_beyond,
    wrap_beyond - starting_offset,
    tokens,
  )
  case list.length(lines) > 1 {
    True -> #(lines, last_line_length)
    False -> #(lines, last_line_length + starting_offset)
  }
}

// ************************************************************
// line last_to_first concatenation
// ************************************************************

fn lines_last_to_first_concatenation_where_first_lines_are_already_reversed(
  l1: List(TextLine),
  l2: List(TextLine),
) -> List(TextLine) {
  let assert [first1, ..rest1] = l1
  let assert [first2, ..rest2] = l2
  pour(
    rest1,
    [
      TextLine(first1.blame, first1.content <> first2.content),
      ..rest2
    ]
  )
}

pub fn last_to_first_concatenation_in_list_list_of_lines_where_all_but_last_list_are_already_reversed(
  list_of_lists: List(List(TextLine))
) -> List(TextLine) {
  case list_of_lists {
    [] -> panic as "this is unexpected"
    [one] -> one
    [next_to_last, last] -> lines_last_to_first_concatenation_where_first_lines_are_already_reversed(next_to_last, last)
    [first, ..rest] -> lines_last_to_first_concatenation_where_first_lines_are_already_reversed(
      first,
      last_to_first_concatenation_in_list_list_of_lines_where_all_but_last_list_are_already_reversed(rest)
    )
  }
}

pub fn t_t_last_to_first_concatenation(node1: VXML, node2: VXML) -> VXML {
  let assert T(blame1, lines1) = node1
  let assert T(_, lines2) = node2
  T(
    blame1,
    lines_last_to_first_concatenation_where_first_lines_are_already_reversed(
      lines1 |> list.reverse,
      lines2
    )
  )
}

fn last_to_first_concatenation_internal(
  remaining: List(VXML),
  already_done: List(VXML),
  current_t: Option(VXML)
) {
  case remaining {
    [] -> case current_t {
      None -> already_done |> list.reverse
      Some(t) -> [t, ..already_done] |> list.reverse
    }
    [V(_, _, _, _) as first, ..rest] -> case current_t {
      None -> last_to_first_concatenation_internal(
        rest,
        [first, ..already_done],
        None
      )
      Some(t) -> last_to_first_concatenation_internal(
        rest,
        [first, t, ..already_done],
        None,
      )
    }
    [T(_, _) as first, ..rest] -> case current_t {
      None -> last_to_first_concatenation_internal(
        rest,
        already_done,
        Some(first)
      )
      Some(t) -> last_to_first_concatenation_internal(
        rest,
        already_done,
        Some(t_t_last_to_first_concatenation(t, first))
      )
    }
  }
}

pub fn last_to_first_concatenation(vxmls: List(VXML)) -> List(VXML) {
  last_to_first_concatenation_internal(vxmls, [], None)
}

fn nonempty_list_t_plain_concatenation(nodes: List(VXML)) -> VXML {
  let assert [first, ..] = nodes
  let assert T(blame, _) = first
  let all_lines = {
    nodes
    |> list.map(fn(node) {
      let assert T(_, blamed_lines) = node
      blamed_lines
    })
    |> list.flatten
  }
  T(blame, all_lines)
}

pub fn plain_concatenation_in_list(nodes: List(VXML)) -> List(VXML) {
  nodes
  |> either_or_misceginator(is_text_node)
  |> regroup_eithers_no_empty_lists
  |> map_either_ors(
    fn(either: List(VXML)) -> VXML { nonempty_list_t_plain_concatenation(either) },
    fn(or: VXML) -> VXML { or },
  )
}

// ************************************************************
// t
// ************************************************************

pub fn is_t_and_is_whitespace(
  vxml: VXML
) -> Bool {
  case vxml {
    T(_, lines) -> lines_are_whitespace(lines)
    _ -> False
  }
}

pub fn is_t_and_text_contains(
  vxml: VXML,
  content: String,
) -> Bool {
  case vxml {
    T(_, lines) -> lines_contain(lines, content)
    _ -> False
  }
}

pub fn t_total_chars(
  vxml: VXML
) -> Int {
  let assert T(_, lines) = vxml
  lines_total_chars(lines)
}

pub fn total_chars( // yeah yeah it's not t-... ...relax a bit...
  vxml: VXML
) -> Int {
  case vxml {
    T(_, lines) ->
      lines_total_chars(lines)

    V(_, _, _, children) ->
      children
      |> list.map(total_chars)
      |> int.sum
  }
}

pub fn t_remove_starting_empty_lines(vxml: VXML) -> Option(VXML) {
  let assert T(blame, lines) = vxml
  let lines = lines_remove_starting_empty_lines(lines)
  case lines {
    [] -> None
    _ -> Some(T(blame, lines))
  }
}

pub fn t_remove_ending_empty_lines(vxml: VXML) -> Option(VXML) {
  let assert T(blame, lines) = vxml
  let lines = lines_remove_starting_empty_lines(lines |> list.reverse) |> list.reverse
  case lines {
    [] -> None
    _ -> Some(T(blame, lines))
  }
}

pub fn t_trim_start(node: VXML) -> Option(VXML) {
  let assert T(blame, lines) = node
  case lines_trim_start(lines) {
    [] -> None
    lines -> Some(T(blame, lines))
  }
}

pub fn t_trim_end(node: VXML) -> Option(VXML) {
  let assert T(blame, lines) = node
  case reversed_lines_trim_end(lines |> list.reverse) {
    [] -> None
    lines -> Some(T(blame, lines |> list.reverse))
  }
}

pub fn t_super_trim_end(node: VXML) -> Option(VXML) {
  let assert T(blame, lines) = node
  let lines =
    lines
    |> list.reverse
    |> list.take_while(fn(line) { string.trim_end(line.content) == "" })
  case lines {
    [] -> None
    _ -> Some(T(blame, lines |> list.reverse))
  }
}

pub fn t_super_trim_end_and_remove_ending_period(node: VXML) -> Option(VXML) {
  let assert T(blame, lines) = node

  let lines =
    lines
    |> list.reverse
    |> list.drop_while(fn(line) { string.trim_end(line.content) == "" })

  case lines {
    [] -> None
    [last, ..rest] -> {
      let content = string.trim_end(last.content)
      case string.ends_with(content, ".") && !string.ends_with(content, "..") {
        True -> {
          let last = TextLine(..last, content: {content |> string.drop_end(1)})
          T(blame, [last, ..rest] |> list.reverse)
          |> t_super_trim_end_and_remove_ending_period
        }
        False -> Some(T(blame, [last, ..rest] |> list.reverse))
      }
    }
  }
}

pub fn t_drop_start(node: VXML, to_drop: Int) -> VXML {
  let assert T(blame, lines) = node
  let assert [first, ..rest] = lines
  T(blame, [TextLine(first.blame, string.drop_start(first.content, to_drop) ), ..rest])
}

pub fn t_drop_end(node: VXML, to_drop: Int) -> VXML {
  let assert T(blame, lines) = node
  let assert [first, ..rest] = lines |> list.reverse
  T(blame, [TextLine(first.blame, string.drop_end(first.content, to_drop) ), ..rest] |> list.reverse)
}

pub fn t_extract_starting_spaces(node: VXML) -> #(Option(VXML), VXML) {
  let assert T(blame, lines) = node
  let assert [first, ..rest] = lines
  case extract_trim_start(first.content) {
    #("", _) -> #(None, node)
    #(spaces, not_spaces) -> #(
      Some(T(first.blame, [TextLine(first.blame, spaces)])),
      T(blame, [TextLine(first.blame, not_spaces), ..rest]),
    )
  }
}

pub fn t_extract_ending_spaces(node: VXML) -> #(Option(VXML), VXML) {
  let assert T(blame, lines) = node
  let assert [first, ..rest] = lines |> list.reverse
  case extract_trim_end(first.content) {
    #("", _) -> #(None, node)
    #(spaces, not_spaces) -> #(
      Some(T(first.blame, [TextLine(first.blame, spaces)])),
      T(blame, [TextLine(first.blame, not_spaces), ..rest] |> list.reverse),
    )
  }
}

pub fn t_start_insert_line(node: VXML, line: TextLine) {
  let assert T(blame, lines) = node
  T(blame, [line, ..lines])
}

pub fn t_end_insert_line(node: VXML, line: TextLine) {
  let assert T(blame, lines) = node
  T(blame, list.append(lines, [line]))
}

pub fn t_start_insert_text(node: VXML, text: String) {
  let assert T(blame, lines) = node
  let assert [TextLine(blame_first, content_first), ..other_lines] = lines
  T(
    blame,
    [TextLine(blame_first, text <> content_first), ..other_lines]
  )
}

pub fn t_end_insert_text(node: VXML, text: String) {
  let assert T(blame, lines) = node
  let assert [TextLine(blame_last, content_last), ..other_lines] =
    lines |> list.reverse
  T(
    blame,
    [TextLine(blame_last, content_last <> text), ..other_lines]
      |> list.reverse,
  )
}

/// "word" == "non-whitespace" == empty string if string ends with
/// whitespace
///
/// returns: -> #(everything_before, after_last_space)
fn break_out_last_word(input: String) -> #(String, String) {
  case input |> string.reverse |> string.split_once(" ") {
    Ok(#(yoro, rest)) -> #(
      { " " <> rest } |> string.reverse,
      yoro |> string.reverse,
    )
    _ -> #("", input)
  }
}

/// "word" == "non-whitespace" == empty string if string
/// starts with whitespace
///
/// returns: -> #(before_first_space, everything_afterwards)
pub fn break_out_first_word(input: String) -> #(String, String) {
  case input |> string.split_once(" ") {
    Ok(#(yoro, rest)) -> #(yoro, " " <> rest)
    _ -> #(input, "")
  }
}

/// "word" == "non-whitespace" == empty string if node
/// ends with whitespace
///
/// returns -> #(
///   node leftover with last word taken out,
///   Option(new T(_, _) containing last word),
/// )
pub fn extract_last_word_from_t_node_if_t(vxml: VXML) -> #(VXML, Option(VXML)) {
  case vxml {
    V(_, _, _, _) -> #(vxml, None)
    T(blame, contents) -> {
      let reversed = contents |> list.reverse
      let assert [last, ..rest] = reversed
      case break_out_last_word(last.content) {
        #(_, "") -> #(vxml, None)
        #(before_last_word, last_word) -> {
          let contents =
            [TextLine(last.blame, before_last_word), ..rest]
            |> list.reverse
          #(
            T(blame, contents),
            Some(T(last.blame, [TextLine(last.blame, last_word)])),
          )
        }
      }
    }
  }
}

/// "word" == "non-whitespace" == empty string if node
/// starts with whitespace
///
/// returns -> #(
///   Option(new T(_, _) containing first word),
///   node leftover with word taken out,
/// )
pub fn extract_first_word_from_t_node_if_t(vxml: VXML) -> #(Option(VXML), VXML) {
  case vxml {
    V(_, _, _, _) -> #(None, vxml)
    T(blame, contents) -> {
      let assert [first, ..rest] = contents
      case break_out_first_word(first.content) {
        #("", _) -> #(None, vxml)
        #(first_word, after_first_word) -> {
          let contents = [TextLine(first.blame, after_first_word), ..rest]
          #(
            Some(T(first.blame, [TextLine(first.blame, first_word)])),
            T(blame, contents),
          )
        }
      }
    }
  }
}

// ************************************************************
// v
// ************************************************************

pub fn v_attrs_constructor(
  blame: Blame,
  tag: String,
  attrs: List(#(String, String)),
) -> VXML {
  let attrs = list.map(attrs, fn(pair) { Attribute(blame, pair.0, pair.1) })
  V(blame, tag, attrs, [])
}

pub fn v_set_tag(
  v: VXML,
  tag: String,
) -> VXML {
  let assert V(_, _, _, _) = v
  V(..v, tag: tag)
}

pub fn v_extract_starting_spaces(node: VXML) -> #(Option(VXML), VXML) {
  let assert V(blame, tag, attrs, children) = node
  case children {
    [T(_, _) as first, ..rest] -> {
      case t_extract_starting_spaces(first) {
        #(None, _) -> #(None, node)
        #(Some(guy), first) -> #(
          Some(guy),
          V(blame, tag, attrs, [first, ..rest]),
        )
      }
    }
    _ -> #(None, node)
  }
}

pub fn v_extract_ending_spaces(node: VXML) -> #(Option(VXML), VXML) {
  let assert V(blame, tag, attrs, children) = node
  case children |> list.reverse {
    [T(_, _) as first, ..rest] -> {
      case t_extract_ending_spaces(first) {
        #(None, _) -> #(None, node)
        #(Some(guy), first) -> #(
          Some(guy),
          V(blame, tag, attrs, [first, ..rest] |> list.reverse),
        )
      }
    }
    _ -> #(None, node)
  }
}

pub fn v_trim_start(node: VXML) -> VXML {
  let assert V(_, _, _, children) = node
  case children {
    [T(_, _) as first, ..rest] -> {
      case t_trim_start(first) {
        None -> v_trim_start(V(..node, children: rest))
        Some(guy) -> V(..node, children: [guy, ..rest])
      }
    }
    _ -> node
  }
}

pub fn v_trim_end(node: VXML) -> VXML {
  let assert V(_, _, _, children) = node
  case children |> list.reverse {
    [T(_, _) as first, ..rest] -> {
      case t_trim_end(first) {
        None -> v_trim_end(V(..node, children: rest |> list.reverse))
        Some(guy) -> V(..node, children: [guy, ..rest] |> list.reverse)
      }
    }
    _ -> node
  }
}

pub fn v_remove_starting_empty_lines(node: VXML) -> VXML {
  let assert V(_, _, _, children) = node
  case children {
    [T(_, _) as first, ..rest] -> {
      case t_remove_starting_empty_lines(first) {
        None -> v_remove_starting_empty_lines(V(..node, children: rest))
        Some(guy) -> V(..node, children: [guy, ..rest])
      }
    }
    _ -> node
  }
}

pub fn v_remove_ending_empty_lines(node: VXML) -> VXML {
  let assert V(_, _, _, children) = node
  case children |> list.reverse {
    [T(_, _) as first, ..rest] -> {
      case t_remove_ending_empty_lines(first) {
        None -> v_remove_ending_empty_lines(V(..node, children: rest |> list.reverse))
        Some(guy) -> V(..node, children: [guy, ..rest] |> list.reverse)
      }
    }
    _ -> node
  }
}

pub fn v_start_insert_line(vxml: VXML, line: TextLine) -> VXML {
  let assert V(blame, _, _, children) = vxml
  let children = case children {
    [T(_, _) as first, ..rest] -> [t_start_insert_line(first, line), ..rest]
    _ -> [T(blame, [line]), ..children]
  }
  V(..vxml, children: children)
}

pub fn v_end_insert_line(vxml: VXML, line: TextLine) -> VXML {
  let assert V(blame, _, _, children) = vxml
  let children = case children |> list.reverse {
    [T(_, _) as first, ..rest] -> [t_end_insert_line(first, line), ..rest]
    _ -> [T(blame, [line]), ..children]
  }
  V(..vxml, children: children |> list.reverse)
}

pub fn v_start_insert_text(vxml: VXML, text: String) -> VXML {
  let assert V(blame, _, _, children) = vxml
  let children = case children {
    [T(_, _) as first, ..rest] -> [t_start_insert_text(first, text), ..rest]
    _ -> [T(blame, [TextLine(blame, text)]), ..children]
  }
  V(..vxml, children: children)
}

pub fn v_end_insert_text(vxml: VXML, text: String) -> VXML {
  let assert V(blame, _, _, children) = vxml
  let children = case children |> list.reverse {
    [T(_, _) as first, ..rest] -> [t_end_insert_text(first, text), ..rest]
    _ -> [T(blame, [TextLine(blame, text)]), ..children]
  }
  V(..vxml, children: children |> list.reverse)
}

pub fn v_get_children(vxml: VXML) -> List(VXML) {
  let assert V(_, _, _, children) = vxml
  children
}

pub fn v_get_tag(vxml: VXML) -> String {
  let assert V(_, tag, _, _) = vxml
  tag
}

pub fn v_prepend_attribute(vxml: VXML, attr: Attribute) {
  let assert V(blame, tag, attrs, children) = vxml
  V(blame, tag, [attr, ..attrs], children)
}

pub fn v_prepend_unique_key_attribute(
  vxml: VXML,
  attr: Attribute,
) -> Result(VXML, Nil) {
  case v_has_attribute_with_key(vxml, attr.key) {
    True -> Error(Nil)
    False -> Ok(v_prepend_attribute(vxml, attr))
  }
}

pub fn v_prepend_child(vxml: VXML, child: VXML) {
  let assert V(blame, tag, attributes, children) = vxml
  V(blame, tag, attributes, [child, ..children])
}

pub fn v_first_attribute_with_key(
  vxml: VXML,
  key: String,
) -> Option(Attribute) {
  let assert V(_, _, attrs, _) = vxml
  case list.find(attrs, fn(b) { b.key == key })
  {
    Error(Nil) -> None
    Ok(thing) -> Some(thing)
  }
}

pub fn v_attributes_with_key(
  vxml: VXML,
  key: String,
) -> List(Attribute) {
  let assert V(_, _, attrs, _) = vxml
  attrs
  |> list.filter(fn(b) {b.key == key})
}

pub fn v_has_attribute_with_key(vxml: VXML, key: String) -> Bool {
  let assert V(_, _, attrs, _) = vxml
  let to_return = list.any(attrs, fn(b) {b.key == key})
  let assert True = to_return == attributes_have_key(attrs, key)
  to_return
}

pub fn is_v_and_has_attribute_with_key(vxml: VXML, key: String) -> Bool {
  case vxml {
    V(_, _, _, _) -> v_has_attribute_with_key(vxml, key)
    _ -> False
  }
}

pub fn v_has_key_value(vxml: VXML, key: String, value: String) -> Bool {
  let assert V(_, _, attrs, _) = vxml
  case list.find(attrs, fn(b) { b.key == key && b.value == value }) {
    Error(Nil) -> False
    Ok(_) -> True
  }
}

pub fn v_extract_children(vxml: VXML, condition: fn(VXML) -> Bool) -> #(VXML, List(VXML)) {
  let assert V(_, _, _, children) = vxml
  let #(extracted, left) = list.partition(children, condition)
  #(V(..vxml, children: left), extracted)
}

pub fn v_filter_children(vxml: VXML, condition: fn(VXML) -> Bool) -> List(VXML) {
  let assert V(_, _, _, children) = vxml
  list.filter(children, condition)
}

pub fn v_children_with_tag(vxml: VXML, tag: String) -> List(VXML) {
  v_filter_children(vxml, is_v_and_tag_equals(_, tag))
}

pub fn v_children_with_tags(vxml: VXML, tags: List(String)) -> List(VXML) {
  v_filter_children(vxml, fn (node){ tags |> list.any(is_v_and_tag_equals(node, _)) })
}

pub fn v_children_with_class(vxml: VXML, class: String) -> List(VXML) {
  v_filter_children(vxml, has_class(_, class))
}

pub fn v_tag_is_one_of(vxml: VXML, tags: List(String)) -> Bool {
  let assert V(_, tag, _, _) = vxml
  list.contains(tags, tag)
}

pub fn v_index_filter_children(
  vxml: VXML,
  condition: fn(VXML) -> Bool,
) -> List(#(VXML, Int)) {
  let assert V(_, _, _, children) = vxml
  children
  |> list.filter(condition)
  |> list.index_map(fn(v, idx) { #(v, idx) })
}

pub fn v_index_children_with_tag(vxml: VXML, tag: String) -> List(#(VXML, Int)) {
  v_index_filter_children(vxml, is_v_and_tag_equals(_, tag))
}

pub fn v_unique_child_with_tag(
  vxml: VXML,
  tag: String,
) -> Result(VXML, SingletonError) {
  v_children_with_tag(vxml, tag)
  |> read_singleton
}

pub fn v_replace_children_with(node: VXML, children: List(VXML)) {
  case node {
    V(b, t, a, _) -> V(b, t, a, children)
    _ -> node
  }
}

pub fn v_append_classes(
  node: VXML,
  classes: String,
) -> VXML {
  let assert V(blame, _, attributes, _) = node
  V(
    ..node,
    attributes: append_to_class_attribute(attributes, blame, classes),
  )
}

pub fn v_append_classes_if(
  node: VXML,
  classes: String,
  condition: fn(VXML) -> Bool,
) -> VXML {
  case condition(node) {
    True -> v_append_classes(node, classes)
    False -> node
  }
}

pub fn v_assert_pop_attribute(vxml: VXML, key: String) -> #(VXML, Attribute) {
  let assert V(b, t, a, c) = vxml
  let assert #([unique_guy_with_key], other_guys) = list.partition(a, fn(b){ b.key == key })
  #(V(b, t, other_guys, c), unique_guy_with_key)
}

pub fn v_assert_pop_attribute_value(vxml: VXML, key: String) -> #(VXML, String) {
  let #(vxml, Attribute(_, _, value)) = v_assert_pop_attribute(vxml, key)
  #(vxml, value)
}

// ************************************************************
// Attribute
// ************************************************************

pub fn keys(attrs: List(Attribute)) -> List(String) {
  attrs |> list.map(fn(attr) { attr.key })
}

pub fn attributes_have_key(
  attrs: List(Attribute),
  key: String,
) -> Bool {
  list.any(attrs, fn(x) { x.key == key })
}

pub fn string_pair_2_attribute(
  pair: #(String, String),
  blame: Blame,
) {
  Attribute(blame, pair.0, pair.1)
}

pub fn string_pairs_2_attributes(
  pairs: List(#(String, String)),
  blame: Blame,
) {
  pairs
  |> list.map(string_pair_2_attribute(_, blame))
}

// ************************************************************
// validation
// ************************************************************

pub fn valid_tag(tag: String) -> Bool {
  case vxml.validate_tag(tag) {
    Ok(_) -> True
    Error(_) -> False
  }
}

pub fn invalid_tag(tag: String) -> Bool {
  case vxml.validate_tag(tag) {
    Ok(_) -> False
    Error(_) -> True
  }
}

// ************************************************************
// is_
// ************************************************************

pub fn is_v_and_has_key_value(vxml: VXML, key: String, value: String) -> Bool {
  case vxml {
    T(_, _) -> False
    _ -> {
      v_has_key_value(vxml, key, value)
    }
  }
}

pub fn is_v_and_tag_equals(vxml: VXML, tag: String) -> Bool {
  case vxml {
    T(_, _) -> False
    V(_, t, _, _) -> t == tag
  }
}

pub fn is_v_and_tag_not_equals(vxml: VXML, tag: String) -> Bool {
  case vxml {
    T(_, _) -> False
    V(_, t, _, _) -> t != tag
  }
}

pub fn is_v_and_tag_is_one_of(vxml: VXML, tags: List(String)) -> Bool {
  case vxml {
    T(_, _) -> False
    V(_, tag, _, _) -> list.contains(tags, tag)
  }
}

pub fn is_text_node(node: VXML) -> Bool {
  case node {
    T(_, _) -> True
    V(_, _, _, _) -> False
  }
}

pub fn is_text_or_is_one_of(node: VXML, tags: List(String)) -> Bool {
  case node {
    T(_, _) -> True
    V(_, tag, _, _) -> list.contains(tags, tag)
  }
}

pub fn has_text_child(node: VXML) {
  case node {
    T(_, _) -> False
    V(_, _, _, children) -> list.any(children, is_text_node)
  }
}

// ************************************************************
// class
// ************************************************************

pub fn has_class(vxml: VXML, class: String) -> Bool {
  case vxml {
    T(_, _) -> False
    _ -> {
      case v_first_attribute_with_key(vxml, "class") {
        Some(Attribute(_, "class", vals)) -> {
          vals
          |> string.split(" ")
          |> list.contains(class)
        }
        _ -> False
      }
    }
  }
}

pub fn concatenate_classes(a: String, b: String) -> String {
  let all_a = a |> string.split(" ") |> list.filter(fn(s){!string.is_empty(s)}) |> list.map(string.trim)
  let all_b = b |> string.split(" ") |> list.filter(fn(s){!string.is_empty(s)}) |> list.map(string.trim)
  let all = list.flatten([all_a, all_b])
  list.fold(all, [], append_if_not_present)
  |> string.join(" ")
}

pub fn append_to_class_attribute(attrs: List(Attribute), blame: Blame, classes: String) -> List(Attribute) {
  let #(index, new_attribute) = list.index_fold(
    attrs,
    #(-1, Attribute(blame, "", "")),
    fn (acc, attr, i) {
      case acc.0, attr.key {
        -1, "class" -> #(i, Attribute(..attr, value: concatenate_classes(attr.value, classes)))
        _, _ -> acc
      }
    }
  )
  case index >= 0 {
    True -> list_set(attrs, index, new_attribute)
    False -> list.append(attrs, [Attribute(blame, "class", concatenate_classes("", classes))])
  }
}

// ************************************************************
// iteration
// ************************************************************

pub fn v_map(
  vxmls: List(VXML),
  f: fn(VXML) -> VXML
) -> List(VXML) {
  list.map(
    vxmls,
    fn(vxml) {
      case vxml {
        T(_, _) -> vxml
        V(_, _, _, _) -> f(vxml)
      }
    }
  )
}

pub fn t_map(
  vxmls: List(VXML),
  f: fn(VXML) -> VXML
) -> List(VXML) {
  list.map(
    vxmls,
    fn(vxml) {
      case vxml {
        T(_, _) -> f(vxml)
        V(_, _, _, _) -> vxml
      }
    }
  )
}

// ************************************************************
// AssertiveTest running
// ************************************************************

pub type AssertiveTest {
  AssertiveTest(
    constructor: fn() -> Desugarer,
    source: String,      // VXML String
    expected: String,    // VXML String
  )
}

pub type AssertiveTestCollection {
  AssertiveTestCollection(
    desugarer_name: String,
    tests: fn() -> List(AssertiveTest),
  )
}

pub type AssertiveTestDataNoParam {
  AssertiveTestDataNoParam(
    source: String,
    expected: String,
  )
}

pub type AssertiveTestData(a) {
  AssertiveTestData(
    param: a,
    source: String,
    expected: String,
  )
}

pub type AssertiveTestDataNoParamWithOutside {
  AssertiveTestDataNoParamWithOutside(
    outside: List(String),
    source: String,
    expected: String,
  )
}

pub type AssertiveTestDataWithOutside(a) {
  AssertiveTestDataWithOutside(
    param: a,
    outside: List(String),
    source: String,
    expected: String,
  )
}

pub type AssertiveTestError {
  VXMLParseError(vxml.VXMLParseError)
  TestDesugaringError(DesugaringError)
  AssertiveTestError(name: String, output: VXML, expected: VXML)
  NonMatchingDesugarerName(String)
}

fn remove_minimum_indent(s: String) -> String {
  let lines = s |> string.split("\n") |> list.filter(fn(line) { string.trim(line) != "" })

  let minimum_indent =
    lines
    |> list.map(fn(line) { string.length(line) - string.length(string.trim_start(line)) })
    |> list.sort(int.compare)
    |> list.first
    |> result.unwrap(0)

  lines |> list.map(fn(line) { line |> string.drop_start(minimum_indent) }) |> string.join("\n")
}

pub fn assertive_test_collection_from_data_no_param(
  name: String,
  datas: List(AssertiveTestDataNoParam),
  constructor: fn() -> Desugarer,
) -> AssertiveTestCollection {
  AssertiveTestCollection(
    desugarer_name: name,
    tests: fn() -> List(AssertiveTest) {
      list.map(
        datas,
        fn(data) {
          AssertiveTest(
            constructor: constructor,
            source: data.source |> remove_minimum_indent,
            expected: data.expected |> remove_minimum_indent
          )
        }
      )
    }
  )
}

pub fn assertive_test_collection_from_data(
  name: String,
  datas: List(AssertiveTestData(a)),
  constructor: fn(a) -> Desugarer,
) -> AssertiveTestCollection {
  AssertiveTestCollection(
    desugarer_name: name,
    tests: fn() -> List(AssertiveTest) {
      list.map(
        datas,
        fn(data) {
          AssertiveTest(
            constructor: fn() { constructor(data.param) },
            source: data.source |> remove_minimum_indent,
            expected: data.expected |> remove_minimum_indent
          )
        }
      )
    }
  )
}

pub fn assertive_test_collection_from_data_no_param_with_outside(
  name: String,
  datas: List(AssertiveTestDataNoParamWithOutside),
  constructor: fn(List(String)) -> Desugarer,
) -> AssertiveTestCollection {
  AssertiveTestCollection(
    desugarer_name: name,
    tests: fn() -> List(AssertiveTest) {
      list.map(
        datas,
        fn(data) {
          AssertiveTest(
            constructor: fn() { constructor(data.outside) },
            source: data.source |> remove_minimum_indent,
            expected: data.expected |> remove_minimum_indent
          )
        }
      )
    }
  )
}

pub fn assertive_test_collection_from_data_with_outside(
  name: String,
  datas: List(AssertiveTestDataWithOutside(a)),
  constructor: fn(a, List(String)) -> Desugarer,
) -> AssertiveTestCollection {
  AssertiveTestCollection(
    desugarer_name: name,
    tests: fn() -> List(AssertiveTest) {
      list.map(
        datas,
        fn(data) {
          AssertiveTest(
            constructor: fn() { constructor(data.param, data.outside) },
            source: data.source |> remove_minimum_indent,
            expected: data.expected |> remove_minimum_indent
          )
        }
      )
    }
  )
}

pub fn run_assertive_test(name: String, tst: AssertiveTest) -> Result(Nil, AssertiveTestError) {
  let desugarer = tst.constructor()
  use <- on.true_false(
    name != desugarer.name,
    Error(NonMatchingDesugarerName(desugarer.name)),
  )
  use vxmls <- result.try(vxml.parse_string(tst.source, "tst.source") |> result.map_error(fn(e) { VXMLParseError(e) }))
  let assert [input] = vxmls
  use vxmls <- result.try(vxml.parse_string(tst.expected, "tst.expect") |> result.map_error(fn(e) { VXMLParseError(e) }))
  let assert [expected] = vxmls
  use #(output, _) <- result.try(
    desugarer.transform(input)
    |> result.map_error(fn(e) { TestDesugaringError(e) })
  )
  case vxml_to_string(output) == vxml_to_string(expected) {
    True -> Ok(Nil)
    False -> Error(
      AssertiveTestError(
        desugarer.name,
        output,
        expected,
      )
    )
  }
}

pub fn run_and_announce_results(
  test_group: AssertiveTestCollection,
  tst: AssertiveTest,
  number: Int,
  total: Int,
) -> Int {
  case run_assertive_test(test_group.desugarer_name, tst) {
    Ok(Nil) -> {
      io.print("✅")
      0
    }
    Error(error) -> {
      io.print("\n❌ test " <> ins(number) <> " of " <> ins(total) <> " failed:")
      case error {
        AssertiveTestError(_, obtained, expected) -> {
          io.println(" obtained != expected:")
          vxml.echo_vxml(obtained, "obtained")
          vxml.echo_vxml(expected, "expected")
          Nil
        }
        _ -> io.println(ins(error))
      }
      1
    }
  }
}

fn run_assertive_test_collection(test_group: AssertiveTestCollection) -> #(Int, Int) {
  let tests = test_group.tests()
  let total = list.length(tests)
  use <- on.false_true(
    total > 0,
    #(0, 0),
  )
  io.print(test_group.desugarer_name <> " ")
  let #(num_success, num_failures) = list.fold(
    tests,
    #(0, 0),
    fn (acc, tst) {
      let failure = run_and_announce_results(test_group, tst, acc.0 + acc.1 + 1, total)
      #(acc.0 + 1 - failure, acc.1 + failure)
    }
  )
  case list.length(tests) == 1 {
    True -> io.println(" (1 assertive test)")
    False -> io.println(" (" <> ins(num_success) <> " assertive tests)")
  }
  #(num_success, num_failures)
}

pub fn run_assertive_desugarer_tests(
  desugarer_names names: List(String),
  available_collections colls: List(AssertiveTestCollection),
) {
  let #(all, dont_have_tests) =
    list.fold(
      colls,
      #([], []),
      fn(acc, coll) {
        case list.length(coll.tests()) > 0 {
          True -> #(
            [coll.desugarer_name, ..acc.0],
            acc.1,
          )
          False -> #(
            [coll.desugarer_name, ..acc.0],
            [coll.desugarer_name, ..acc.1],
          )
        }
      }
    )

  let names = case list.is_empty(names) {
    True -> all
    False -> names
  }

  let dont_have_tests = list.filter(dont_have_tests, list.contains(names, _))

  case list.is_empty(dont_have_tests) {
    True -> Nil
    False -> {
      io.println("")
      io.println("the following desugarers have empty test data:")
      list.each(
        dont_have_tests,
        fn(name) { io.println(" - " <> name)}
      )
    }
  }

  io.println("")
  let #(num_performed, num_failed) =
    list.fold(
      colls,
      #(0, 0),
      fn(acc, coll) {
        case {
          list.contains(names, coll.desugarer_name) &&
          list.length(coll.tests()) > 0
        } {
          False -> acc
          True -> {
            let #(_, num_failed) = run_assertive_test_collection(coll)
            case num_failed > 0 {
              True -> #(acc.0 + 1, acc.1 + 1)
              False -> #(acc.0 + 1, acc.1)
            }
          }
        }
      }
    )

  io.println("")
  io.println(
    ins(num_performed)
    <> case num_performed == 1 {
      True -> " desugarer tested, "
      False -> " desugarers tested, "
    }
    <> ins(num_failed)
    <> case num_failed == 1 {
      True -> " failed"
      False -> " failures"
    }
  )

  let desugarers_with_no_test_group = list.filter(names, fn(name) { !list.contains(all, name)})
  case list.is_empty(desugarers_with_no_test_group) {
    True -> Nil
    False -> {
      io.println("")
      io.println("could not find any test data for the following desugarers:")
      list.each(
        desugarers_with_no_test_group,
        fn(name) { io.println(" - " <> name)}
      )
    }
  }

  Nil
}

// ************************************************************
// Desugarer types
// ************************************************************

pub type DesugaringError {
  DesugaringError(blame: Blame, message: String)
}

pub type DesugaringWarning {
  DesugaringWarning(blame: Blame, message: String)
}

pub type DesugarerTransform =
  fn(VXML) -> Result(#(VXML, List(DesugaringWarning)), DesugaringError)

pub type Desugarer {
  Desugarer(
    name: String,
    stringified_param: Option(String),
    stringified_outside: Option(String),
    transform: DesugarerTransform,
  )
}

// ************************************************************
// tracking-related part 1: types
// ************************************************************

/// A VXML instance is serialized into a list of SLine for the
/// purposes of tracking (see "--track" command line option);
/// each SLine (for "Selected (or not) TextLine") is one of four
/// variants:
///
/// - VSLine: a tag "<> ..." of a V-node
/// - ASLine: a key-attribute pair line "key=val" of a V-node
/// - TSLine: the caret "<>" that marks the start of a T-node
/// - LSLine: a content-line for a T-node
///
/// Each SLine comes with a selection status, given by its 'selected'
/// field.
pub type SLine {
  VSLine(blame: Blame, indent: Int, content: String, selected: SLineSelectedStatus, tag: String)
  ASLine(blame: Blame, indent: Int, content: String, selected: SLineSelectedStatus, key: String, val: String)
  TSLine(blame: Blame, indent: Int, content: String, selected: SLineSelectedStatus)
  LSLine(blame: Blame, indent: Int, content: String, selected: SLineSelectedStatus)
}

pub type SLineSelectedStatus {
  NotSelected
  OG
  Bystander
}

pub type TextLineSelector =
  fn(SLine) -> SLineSelectedStatus

pub type Selector =
  fn(List(SLine)) -> List(SLine)

// ************************************************************
// tracking-related part 2: VXML -> List(SLine)
// ************************************************************

fn v_s_line(blame: Blame, indent: Int, tag: String) {
  VSLine(blame, indent, "<> " <> tag, NotSelected, tag)
}

fn a_s_line(blame: Blame, indent: Int, key: String, val: String) {
  ASLine(blame, indent, key <> "=" <> val, NotSelected, key, val)
}

fn t_s_line(blame: Blame, indent: Int) {
  TSLine(blame, indent, "<>", NotSelected)
}

fn l_s_line(blame: Blame, indent: Int, content: String) {
  TSLine(blame, indent, "\"" <> content <> "\"", NotSelected)
}

fn v_s_lines(
  vxml: VXML,
  indent: Int,
) -> List(SLine) {
  let assert V(blame, tag, attributes, _) = vxml
  let attributes =
    attributes
    |> list.map(fn(a) {a_s_line(a.blame, indent + 2, a.key, a.value)})
  [v_s_line(blame, indent, tag), ..attributes]
}

fn t_s_lines(
  vxml: VXML,
  indent: Int,
) -> List(SLine) {
  let assert T(blame, lines) = vxml
  let lines =
    lines
    |> list.map(fn(line) { l_s_line(line.blame, indent + 2, line.content) })
  [t_s_line(blame, indent), ..lines]
}

fn vxml_to_s_lines_internal(
  previous_lines: List(SLine),
  vxml: VXML,
  indent: Int,
) -> List(SLine) {
  case vxml {
    V(_, _, _, children) -> {
      list.fold(
        children,
        pour(v_s_lines(vxml, indent), previous_lines),
        fn(acc, child) {
          vxml_to_s_lines_internal(acc, child, indent + 2)
        }
      )
    }
    T(_, _) -> {
      pour(t_s_lines(vxml, indent), previous_lines)
    }
  }
}

pub fn vxml_to_s_lines(
  vxml: VXML,
) -> List(SLine) {
  vxml_to_s_lines_internal([], vxml, 0)
  |> list.reverse
}

// ************************************************************
// tracking-related part 3: creating an initial selection from a TextLineSelector
// ************************************************************

pub fn apply_line_selector_to_line(
  line: SLine,
  line_selector: TextLineSelector,
) -> SLine {
  let sel = line_selector(line)
  case line {
    VSLine(_, _, _, _, _) -> VSLine(..line, selected: sel)
    ASLine(_, _, _, _, _, _) -> ASLine(..line, selected: sel)
    TSLine(_, _, _, _) -> TSLine(..line, selected: sel)
    LSLine(_, _, _, _) -> LSLine(..line, selected: sel)
  }
}

pub fn line_selector_to_selector(
  line_selector: TextLineSelector,
) -> Selector {
  list.map(
    _,
    apply_line_selector_to_line(_, line_selector)
  )
}

// ************************************************************
// tracking-related part 4: List(SLine) -> List(SLine) operations (extending selections)
// ************************************************************

fn bring_to_bystander_level(line: SLine) -> SLine {
  case line.selected {
    OG | Bystander -> line
    _ -> case line {
      VSLine(_, _, _, _, _) -> VSLine(..line, selected: Bystander)
      ASLine(_, _, _, _, _, _) -> ASLine(..line, selected: Bystander)
      TSLine(_, _, _, _) -> TSLine(..line, selected: Bystander)
      LSLine(_, _, _, _) -> LSLine(..line, selected: Bystander)
    }
  }
}

fn is_v_s_line(line: SLine) -> Bool {
  case line {
    VSLine(_, _, _, _, _) -> True
    _ -> False
  }
}

fn is_a_s_line(line: SLine) -> Bool {
  case line {
    ASLine(_, _, _, _, _, _) -> True
    _ -> False
  }
}

fn is_og(line: SLine) -> Bool {
  line.selected == OG
}

fn extend_selection_down_no_reverse(
  lines: List(SLine),
  amt: Int,
) -> List(SLine) {
  let assert True = amt >= 0
  list.fold(
    lines,
    #(0, []),
    fn(acc, line) {
      let #(gas, lines) = acc
      let gas = case line.selected == OG {
        True -> amt + 1
        False -> gas - 1
      }
      let lines = case gas > 0 {
        True -> [line |> bring_to_bystander_level, ..lines]
        False -> [line, ..lines]
      }
      #(gas, lines)
    }
  )
  |> pair.second
}

pub fn extend_selection_down(
  lines: List(SLine),
  amt: Int,
) -> List(SLine) {
  lines
  |> extend_selection_down_no_reverse(amt)
  |> list.reverse
}

pub fn extend_selection_up(
  lines: List(SLine),
  amt: Int,
) -> List(SLine) {
  lines
  |> list.reverse
  |> extend_selection_down_no_reverse(amt)
}

pub fn extend_selection_to_ancestors(
  lines: List(SLine),
  with_elder_siblings with_siblings: Bool,
  with_attributes with_attributes: Bool,
) -> List(SLine) {
  lines
  |> list.reverse
  |> list.fold(
    #(-1, []),
    fn (acc, line) {
      let #(indent, lines) = acc
      let is_v = is_v_s_line(line)
      let is_a = is_a_s_line(line)
      let line = case {
        line.indent < indent
      } || {
        line.indent == indent && { {is_v && with_siblings} || {is_a && with_attributes} }
      } || {
        line.indent == indent + 2 && with_siblings && is_a && with_attributes
      } {
        True -> line |> bring_to_bystander_level
        False -> line
      }
      let indent = case {
        line.indent < indent && is_v
      } || {
        line.indent > indent && is_og(line)
      } {
        True -> line.indent
        False -> indent
      }
      #(indent, [line, ..lines])
    }
  )
  |> pair.second
}

pub fn extend_selector_up(
  f: Selector,
  amt: Int,
) -> Selector {
  fn (lines) {
    lines
    |> f
    |> extend_selection_up(amt)
  }
}

pub fn extend_selector_down(
  f: Selector,
  amt: Int,
) -> Selector {
  fn (lines) {
    lines
    |> f
    |> extend_selection_down(amt)
  }
}

pub fn extend_selector_to_ancestors(
  f: Selector,
  with_elder_siblings with_siblings: Bool,
  with_attributes with_attributes: Bool,
) -> Selector {
  fn (lines) {
    lines
    |> f
    |> extend_selection_to_ancestors(with_siblings, with_attributes)
  }
}

// ************************************************************
// tracking-related part 5: or-ing Selectors (esoteric, but we do it)
// ************************************************************

fn or_a_pair_of_s_lines(
  l1: SLine,
  l2: SLine,
) -> SLine {
  // let assert True = l1.content == l2.content
  // let assert True = l1.indent == l2.indent
  // let assert True = l1.blame == l2.blame
  case l1.selected, l2.selected {
    OG, _ -> l1
    _, OG -> l2
    Bystander, _ -> l1
    _, Bystander -> l2
    _, _ -> l1
  }
}

fn or_two_lists_of_s_lines(
  l1: List(SLine),
  l2: List(SLine),
) -> List(SLine) {
  let assert True = list.length(l1) == list.length(l2)
  list.map2(l1, l2, or_a_pair_of_s_lines)
}

pub fn or_selectors(
  s1: Selector,
  s2: Selector,
) -> Selector {
  fn (pigeons) {
    let l1 = pigeons |> s1
    let l2 = pigeons |> s2
    or_two_lists_of_s_lines(l1, l2)
  }
}

// ************************************************************
// tracking-related part 6: pretty-printing selections
// ************************************************************

pub fn s_line_2_output_line(line: SLine) -> OutputLine {
  OutputLine(line.blame, line.indent, line.content)
}

pub fn s_lines_2_output_lines(
  lines: List(SLine),
  dry_run: Bool,
) -> List(OutputLine) {
  let s2l = s_line_2_output_line
  lines
  |> list.fold(
    #(False, None, []),
    fn (acc, line) {
      case line.selected {
        OG | Bystander -> case acc.1 {
          None ->
            #(
              True,
              None,
              [line |> s2l, ..acc.2],
            )

          Some(#(indentation, num_lines)) ->
            #(
              True,
              None,
              [line |> s2l, OutputLine(bl.NoBlame([ins(case dry_run {True -> 0 False -> num_lines}) <> " unselected lines"]), indentation, "..."), ..acc.2],
            )
        }
        NotSelected -> case acc.0, acc.1 {
          False, None ->
            #(
              False,
              None,
              acc.2
            )

          True, None ->
            #(
              True,
              Some(#(line.indent, 1)),
              acc.2,
            )

          True, Some(#(indentation, num_lines)) ->
            #(
              True,
              Some(#(int.min(line.indent, indentation), num_lines + 1)),
              acc.2,
            )

          False, Some(_) -> panic as "shouldn't reach this combo"
        }
      }
    }
  )
  |> triple_3rd
  |> list.reverse
}

pub fn s_lines_annotated_table(
  lines: List(SLine),
  banner: String,
  dry_run: Bool,
  indent: Int,
) -> String {
  lines
  |> s_lines_2_output_lines(dry_run)
  |> io_l.output_lines_annotated_table_at_indent(banner, indent)
  |> string.join("\n")
}

// ************************************************************
// Pipeline
// ************************************************************

pub type TrackingMode {
  TrackingOff
  TrackingOnChange
  TrackingForced
}

pub type Pipe {
  Pipe(
    desugarer: Desugarer,
    selector: Selector,
    tracking_mode: TrackingMode,
  )
}

pub type Pipeline =
  List(Pipe)

pub fn pipeline_desugarers(
  pipeline: Pipeline
) -> List(Desugarer) {
  pipeline |> list.map(fn(x) { x.desugarer })
}

pub fn desugarers_2_pipeline(
  desugarers: List(Desugarer),
  selector: Selector,
  tracking_mode: TrackingMode,
) -> Pipeline {
  desugarers
  |> list.map(fn (d) {
    Pipe(
      desugarer: d,
      selector: selector,
      tracking_mode: tracking_mode,
    )
  })
}
