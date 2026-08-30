import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
  type LatexDelimiterPair, DoubleDollar,
}
import desugaring/nodemaps_2_transform as n2t
import gleam/list
import vxml.{type Line, type VXML, Line, T, V}
import vxml/blame as bl

pub const name = "ii2_normalize_begin_end_align"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Adds compatible math delimiters around align
/// environments when they are missing.
pub fn constructor(param: Param) -> Desugarer {
  authoring.desugarer(
    name: name,
    param: param,
    prepare: param_to_inner_param,
    transform: inner_param_to_transform,
  )
}

type Param =
  #(
    // Delimiter pair to insert when one is missing.
    core.LatexDelimiterPair,
    // Delimiter pairs that may already surround an environment.
    List(LatexDelimiterPair),
  )

type InnerParam {
  InnerParam(
    opening_delimiters: List(String),
    opening_replacement: String,
    closing_delimiters: List(String),
    closing_replacement: String,
  )
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  let #(allowed_starts, allowed_ends) =
    param.1
    |> list.map(core.opening_and_closing_string_for_pair)
    |> list.unzip
  let #(prescribed_start, prescribed_end) =
    core.opening_and_closing_string_for_pair(param.0)
  Ok(InnerParam(
    opening_delimiters: allowed_starts,
    opening_replacement: prescribed_start,
    closing_delimiters: allowed_ends,
    closing_replacement: prescribed_end,
  ))
}

fn inner_param_to_transform(inner: InnerParam) -> DesugarerTransform {
  let nodemap: n2t.OneToOneNodemap = nodemap(_, inner)
  nodemap
  |> n2t.one_to_one_nodemap_2_desugarer_transform
}

fn nodemap(vxml: VXML, inner: InnerParam) -> Result(VXML, DesugaringError) {
  case vxml {
    V(_, _, _, _) -> Ok(vxml)
    T(blame, lines) -> {
      let lines =
        lines
        |> split_and_insert_before_unless_allowable_ending_found_ez_version(
          "\\begin{align",
          inner.opening_delimiters,
          inner.opening_replacement,
        )
        |> split_and_insert_after_unless_allowable_beginning_found_ez_version(
          "\\end{align}",
          inner.closing_delimiters,
          inner.closing_replacement,
        )
        |> split_and_insert_after_unless_allowable_beginning_found_ez_version(
          "\\end{align*}",
          inner.closing_delimiters,
          inner.closing_replacement,
        )
      Ok(T(blame, lines))
    }
  }
}

fn split_and_insert_before_unless_allowable_ending_found_ez_version(
  lines: List(Line),
  splitter: String,
  // this will be called with splitter == "\begin{align"
  allowable_endings: List(String),
  // this will almost always be ["$$"], but could be ["\[", "$$"] for ex
  if_no_allowable_found_insert: String,
  // will almost always be "$$"
) -> List(Line) {
  let blame = desugarer_blame(91)

  let add_prescribed_to_end_if_missing = fn(lines) {
    let trimmed =
      lines
      |> list.reverse
      |> core.reversed_lines_trim_end
    case
      list.any(allowable_endings, fn(x) {
        core.first_line_ends_with(trimmed, x)
      })
    {
      True -> trimmed |> list.reverse
      False ->
        [Line(blame, if_no_allowable_found_insert), ..trimmed]
        |> list.reverse
    }
  }

  let add_splitter_back_in = fn(lines) {
    let assert [first, ..rest] = lines
    [Line(..first, content: splitter <> first.content), ..rest]
  }

  // [
  //   "a1 b1 c1 d1",
  //   "a2 b2 c2 \begin{align} d2",
  //   "a3 b3 c3 d3",
  //   "a4 b4 c4 \begin{align} d4",
  //   "a5 b5 c5 d5",
  //   "a6 b6 c6 d6",
  //   "a7 b7 c7 \begin{align} d7",
  // ]
  // 👇
  // splitting on '\begin{align'
  // 👇
  // splits = [
  //   [
  //     "a1 b1 c1 d1",
  //     "a2 b2 c2 ",
  //   ],
  //   [
  //     "} d2",
  //     "a3 b3 c3 d3",
  //     "a4 b4 c4 ",
  //   ],
  //   [
  //     "} d4",
  //     "a5 b5 c5 d5",
  //     "a6 b6 c6 d6",
  //     "a7 b7 c7 ",
  //   ],
  //   [
  //     "} d7",
  //   ],
  // ]

  let splits = core.split_lines(lines, splitter)
  let num_splits = list.length(splits)

  list.index_map(splits, fn(lines, index) {
    lines
    |> do_if(add_splitter_back_in, index > 0)()
    |> do_if(add_prescribed_to_end_if_missing, index < num_splits - 1)()
  })
  |> list.flatten
}

fn split_and_insert_after_unless_allowable_beginning_found_ez_version(
  lines: List(Line),
  splitter: String,
  allowable_beginnings: List(String),
  // this will almost always be ["$$"], but could be ["\]", "$$"] for ex
  if_no_allowable_found_insert: String,
  // this will almost always be "$$"
) -> List(Line) {
  let blame = desugarer_blame(167)

  let add_prescribed_to_start_if_missing = fn(lines) {
    let trimmed = core.lines_trim_start(lines)
    case
      list.any(allowable_beginnings, fn(x) {
        core.first_line_starts_with(trimmed, x)
      })
    {
      True -> trimmed
      False -> [Line(blame, if_no_allowable_found_insert), ..trimmed]
    }
  }

  let add_splitter_back_in = fn(lines) {
    let assert [first, ..rest] = lines |> list.reverse
    [Line(..first, content: first.content <> splitter), ..rest]
    |> list.reverse
  }

  let splits = core.split_lines(lines, splitter)
  let num_splits = list.length(splits)

  list.index_map(splits, fn(lines, index) {
    lines
    |> do_if(add_prescribed_to_start_if_missing, index > 0)()
    |> do_if(add_splitter_back_in, index < num_splits - 1)()
  })
  |> list.flatten
}

// ***
// these 2 'hard version' are faster, less easy to read:
// ***

// fn split_and_insert_before_unless_allowable_ending_found(
//   lines: List(Line),
//   splitter: String,                      // this will be called with splitter == "\begin{align"
//   allowable_endings: List(String),       // this will almost always be ["$$"], but could be ["\[", "$$"] for ex
//   if_no_allowable_found_insert: String,  // will almost always be "$$"
// ) -> List(Line) {
//   let blame = core.blame_us("split_and_insert_before_unless_allowable_ending_found")

//   let add_prescribed_to_end_if_missing = fn(lines) {
//     let trimmed =
//       lines
//       |> list.reverse
//       |> core.reversed_lines_trim_end
//     case list.any(
//       allowable_endings,
//       fn(x) { core.first_line_ends_with(trimmed, x) }
//     ) {
//       True -> [
//         Line(blame, ""),
//         ..trimmed
//       ]
//       False -> [
//         Line(blame, ""),
//         Line(blame, if_no_allowable_found_insert),
//         ..trimmed
//       ]
//     }
//   }

//   let add_splitter_back_in = fn(lines) {
//     let assert [Line(blame, content), ..rest] = lines
//     [
//       Line(blame, splitter <> content),
//       ..rest
//     ]
//   }

//   let splits = core.split_lines(lines, splitter)
//   let num_splits = list.length(splits)

//   list.index_map(
//     splits,
//     fn(lines, index) {
//       lines
//       |> do_if(add_splitter_back_in, index > 0)
//       |> do_if(add_prescribed_to_end_if_missing, index < num_splits - 1)
//     }
//   )
//   |> core.last_to_first_concatenation_in_list_list_of_lines_where_all_but_last_list_are_already_reversed
// }

// fn split_and_insert_after_unless_allowable_beginning_found(
//   lines: List(Line),
//   splitter: String,
//   allowable_beginnings: List(String),    // this will almost always be ["$$"], but could be ["\]", "$$"] for ex
//   if_no_allowable_found_insert: String,  // this will almost always be "$$"
// ) -> List(Line) {
//   let blame = core.blame_us("split_and_insert_after_unless_allowable_beginning_found")

//   let add_prescribed_to_start_if_missing = fn(lines) {
//     let trimmed = core.lines_trim_start(lines)
//     case list.any(
//       allowable_beginnings,
//       fn(x) { core.first_line_starts_with(trimmed, x) }
//     ) {
//       True -> [
//         Line(blame, ""),
//         ..trimmed,
//       ]
//       False -> [
//         Line(blame, ""),
//         Line(blame, if_no_allowable_found_insert),
//         ..trimmed,
//       ]
//     }
//   }

//   let add_splitter_back_in = fn(lines) {
//     let assert [Line(blame, content), ..rest] = list.reverse(lines)
//     [
//       Line(blame, content <> splitter),
//       ..rest
//     ]
//   }

//   let splits = core.split_lines(lines, splitter)
//   let num_splits = list.length(splits)

//   list.index_map(
//     splits,
//     fn(lines, index) {
//       lines
//       |> do_if(add_prescribed_to_start_if_missing, index > 0)
//       |> do_if(add_splitter_back_in, index < num_splits - 1)
//     }
//   )
//   |> core.last_to_first_concatenation_in_list_list_of_lines_where_all_but_last_list_are_already_reversed
// }

fn do_if(f, b) {
  case b {
    True -> f
    False -> fn(x) { x }
  }
}

fn desugarer_blame(line_no: Int) {
  bl.Des([], name, line_no)
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊

fn assertive_tests_data() -> List(core.AssertiveTestData(Param)) {
  [
    core.AssertiveTestData(
      param: #(DoubleDollar, [DoubleDollar]),
      source: "
                <> root
                  <>
                    'Some text'
                    '\\begin{align}'
                    'x = 1'
                    '\\end{align}'
                    'More text'
                ",
      expected: "
                <> root
                  <>
                    'Some text'
                    '$$'
                    '\\begin{align}'
                    'x = 1'
                    '\\end{align}'
                    '$$'
                    'More text'
                ",
    ),
    core.AssertiveTestData(
      param: #(DoubleDollar, [DoubleDollar]),
      source: "
                <> root
                  <>
                    'Some text'
                    '\\begin{align*}'
                    'x = 1'
                    '\\end{align*}'
                    'More text'
                ",
      expected: "
                <> root
                  <>
                    'Some text'
                    '$$'
                    '\\begin{align*}'
                    'x = 1'
                    '\\end{align*}'
                    '$$'
                    'More text'
                ",
    ),
    core.AssertiveTestData(
      param: #(DoubleDollar, [DoubleDollar]),
      source: "
                <> root
                  <>
                    'Some text'
                    '$$ '
                    '\\begin{align}'
                    'x = 1'
                    '\\end{align}'
                    ' $$'
                    'More text'
                ",
      expected: "
                <> root
                  <>
                    'Some text'
                    '$$'
                    '\\begin{align}'
                    'x = 1'
                    '\\end{align}'
                    '$$'
                    'More text'
                ",
    ),
    core.AssertiveTestData(
      param: #(DoubleDollar, [DoubleDollar]),
      source: "
                <> root
                  <>
                    'Some text'
                    '$$\\begin{align*}'
                    'x = 1'
                    '\\end{align*}$$'
                    'More text'
                ",
      expected: "
                <> root
                  <>
                    'Some text'
                    '$$'
                    '\\begin{align*}'
                    'x = 1'
                    '\\end{align*}'
                    '$$'
                    'More text'
                ",
    ),
    core.AssertiveTestData(
      param: #(DoubleDollar, [DoubleDollar]),
      source: "
                <> root
                  <>
                    'Some text'
                    '$$'
                    ''
                    ''
                    '\\begin{align*}'
                    'x = 1'
                    '\\end{align}'
                    ''
                    ''
                    '$$'
                    'More text'
                ",
      expected: "
                <> root
                  <>
                    'Some text'
                    '$$'
                    '\\begin{align*}'
                    'x = 1'
                    '\\end{align}'
                    '$$'
                    'More text'
                ",
    ),
    core.AssertiveTestData(
      param: #(DoubleDollar, [DoubleDollar]),
      source: "
                <> root
                  <>
                    'Some text'
                    '\\begin{align*}'
                    '\\begin{align}'
                    '\\end{align*}$$'
                    'More text'
                ",
      expected: "
                <> root
                  <>
                    'Some text'
                    '$$'
                    '\\begin{align*}'
                    '$$'
                    '\\begin{align}'
                    '\\end{align*}'
                    '$$'
                    'More text'
                ",
    ),
    core.AssertiveTestData(
      param: #(DoubleDollar, [DoubleDollar]),
      source: "
                <> root
                  <>
                    'A'
                    'B'
                    '\\begin{align}\\end{align}'
                    'C'
                    'D'
                    '\\begin{align}\\end{align}'
                    'E'
                    'F'
                    '\\begin{align}\\end{align}'
                    'G'
                    'H'
                ",
      expected: "
                <> root
                  <>
                    'A'
                    'B'
                    '$$'
                    '\\begin{align}\\end{align}'
                    '$$'
                    'C'
                    'D'
                    '$$'
                    '\\begin{align}\\end{align}'
                    '$$'
                    'E'
                    'F'
                    '$$'
                    '\\begin{align}\\end{align}'
                    '$$'
                    'G'
                    'H'
                ",
    ),
  ]
}

pub fn assertive_tests() {
  core.assertive_test_collection_from_data(
    name,
    assertive_tests_data(),
    constructor,
  )
}
