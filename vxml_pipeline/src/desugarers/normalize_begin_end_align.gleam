import gleam/list
import gleam/option
import gleam/string.{inspect as ins}
import infrastructure.{type Desugarer, Desugarer, type DesugarerTransform, type DesugaringError, type LatexDelimiterPair, DoubleDollar} as infra
import nodemaps_2_desugarer_transforms as n2t
import vxml.{type VXML, type TextLine, TextLine, V, T}
import blame as bl

fn do_if(f, b) {
  case b {
    True -> f
    False -> fn(x){x}
  }
}

fn split_and_insert_before_unless_allowable_ending_found_ez_version(
  lines: List(TextLine),
  splitter: String,                      // this will be called with splitter == "\begin{align"
  allowable_endings: List(String),       // this will almost always be ["$$"], but could be ["\[", "$$"] for ex
  if_no_allowable_found_insert: String,  // will almost always be "$$"
) -> List(TextLine) {
  let blame = desugarer_blame(22)

  let add_prescribed_to_end_if_missing = fn(lines) {
    let trimmed =
      lines
      |> list.reverse
      |> infra.reversed_lines_trim_end
    case list.any(
      allowable_endings,
      fn(x) { infra.first_line_ends_with(trimmed, x) }
    ) {
      True -> trimmed |> list.reverse
      False -> [
        TextLine(blame, if_no_allowable_found_insert),
        ..trimmed
      ] |> list.reverse
    }
  }

  let add_splitter_back_in = fn(lines) {
    let assert [first, ..rest] = lines
    [
      TextLine(..first, content: splitter <> first.content),
      ..rest
    ]
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

  let splits = infra.split_lines(lines, splitter)
  let num_splits = list.length(splits)

  list.index_map(
    splits,
    fn(lines, index) {
      lines
      |> do_if(add_splitter_back_in, index > 0)
      |> do_if(add_prescribed_to_end_if_missing, index < num_splits - 1)
    }
  )
  |> list.flatten
}

fn split_and_insert_after_unless_allowable_beginning_found_ez_version(
  lines: List(TextLine),
  splitter: String,
  allowable_beginnings: List(String),    // this will almost always be ["$$"], but could be ["\]", "$$"] for ex
  if_no_allowable_found_insert: String,  // this will almost always be "$$"
) -> List(TextLine) {
  let blame = desugarer_blame(102)

  let add_prescribed_to_start_if_missing = fn(lines) {
    let trimmed = infra.lines_trim_start(lines)
    case list.any(
      allowable_beginnings,
      fn(x) { infra.first_line_starts_with(trimmed, x) }
    ) {
      True -> trimmed
      False -> [
        TextLine(blame, if_no_allowable_found_insert),
        ..trimmed,
      ]
    }
  }

  let add_splitter_back_in = fn(lines) {
    let assert [first, ..rest] = lines |> list.reverse
    [
      TextLine(..first, content: first.content <> splitter),
      ..rest
    ] |> list.reverse
  }

  let splits = infra.split_lines(lines, splitter)
  let num_splits = list.length(splits)

  list.index_map(
    splits,
    fn(lines, index) {
      lines
      |> do_if(add_prescribed_to_start_if_missing, index > 0)
      |> do_if(add_splitter_back_in, index < num_splits - 1)
    }
  )
  |> list.flatten
}

// ***
// these 2 'hard version' are faster, less easy to read:
// ***

// fn split_and_insert_before_unless_allowable_ending_found(
//   lines: List(TextLine),
//   splitter: String,                      // this will be called with splitter == "\begin{align"
//   allowable_endings: List(String),       // this will almost always be ["$$"], but could be ["\[", "$$"] for ex
//   if_no_allowable_found_insert: String,  // will almost always be "$$"
// ) -> List(TextLine) {
//   let blame = infra.blame_us("split_and_insert_before_unless_allowable_ending_found")

//   let add_prescribed_to_end_if_missing = fn(lines) {
//     let trimmed =
//       lines
//       |> list.reverse
//       |> infra.reversed_lines_trim_end
//     case list.any(
//       allowable_endings,
//       fn(x) { infra.first_line_ends_with(trimmed, x) }
//     ) {
//       True -> [
//         TextLine(blame, ""),
//         ..trimmed
//       ]
//       False -> [
//         TextLine(blame, ""),
//         TextLine(blame, if_no_allowable_found_insert),
//         ..trimmed
//       ]
//     }
//   }

//   let add_splitter_back_in = fn(lines) {
//     let assert [TextLine(blame, content), ..rest] = lines
//     [
//       TextLine(blame, splitter <> content),
//       ..rest
//     ]
//   }

//   let splits = infra.split_lines(lines, splitter)
//   let num_splits = list.length(splits)

//   list.index_map(
//     splits,
//     fn(lines, index) {
//       lines
//       |> do_if(add_splitter_back_in, index > 0)
//       |> do_if(add_prescribed_to_end_if_missing, index < num_splits - 1)
//     }
//   )
//   |> infra.last_to_first_concatenation_in_list_list_of_lines_where_all_but_last_list_are_already_reversed
// }

// fn split_and_insert_after_unless_allowable_beginning_found(
//   lines: List(TextLine),
//   splitter: String,
//   allowable_beginnings: List(String),    // this will almost always be ["$$"], but could be ["\]", "$$"] for ex
//   if_no_allowable_found_insert: String,  // this will almost always be "$$"
// ) -> List(TextLine) {
//   let blame = infra.blame_us("split_and_insert_after_unless_allowable_beginning_found")

//   let add_prescribed_to_start_if_missing = fn(lines) {
//     let trimmed = infra.lines_trim_start(lines)
//     case list.any(
//       allowable_beginnings,
//       fn(x) { infra.first_line_starts_with(trimmed, x) }
//     ) {
//       True -> [
//         TextLine(blame, ""),
//         ..trimmed,
//       ]
//       False -> [
//         TextLine(blame, ""),
//         TextLine(blame, if_no_allowable_found_insert),
//         ..trimmed,
//       ]
//     }
//   }

//   let add_splitter_back_in = fn(lines) {
//     let assert [TextLine(blame, content), ..rest] = list.reverse(lines)
//     [
//       TextLine(blame, content <> splitter),
//       ..rest
//     ]
//   }

//   let splits = infra.split_lines(lines, splitter)
//   let num_splits = list.length(splits)

//   list.index_map(
//     splits,
//     fn(lines, index) {
//       lines
//       |> do_if(add_prescribed_to_start_if_missing, index > 0)
//       |> do_if(add_splitter_back_in, index < num_splits - 1)
//     }
//   )
//   |> infra.last_to_first_concatenation_in_list_list_of_lines_where_all_but_last_list_are_already_reversed
// }

fn nodemap(
  vxml: VXML,
  inner: InnerParam
) -> Result(VXML, DesugaringError) {
  case vxml {
    V(_, _, _, _) -> Ok(vxml)
    T(blame, lines) -> {
      let lines =
        lines
        |> split_and_insert_before_unless_allowable_ending_found_ez_version(
          "\\begin{align",
          inner.0,
          inner.1,
        )
        |> split_and_insert_after_unless_allowable_beginning_found_ez_version(
          "\\end{align}",
          inner.2,
          inner.3,
        )
        |> split_and_insert_after_unless_allowable_beginning_found_ez_version(
          "\\end{align*}",
          inner.2,
          inner.3,
        )
      Ok(T(blame, lines))
    }
  }
}

fn nodemap_factory(inner: InnerParam) -> n2t.OneToOneNodeMap {
  nodemap(_, inner)
}

fn transform_factory(inner: InnerParam) -> DesugarerTransform {
  nodemap_factory(inner)
  |> n2t.one_to_one_nodemap_2_desugarer_transform
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  let #(allowed_starts, allowed_ends) =
    param.1
    |> list.map(infra.opening_and_closing_string_for_pair)
    |> list.unzip
  let #(prescribed_start, prescribed_end) =
    infra.opening_and_closing_string_for_pair(param.0)
  #(
    allowed_starts,
    prescribed_start,
    allowed_ends,
    prescribed_end,
  )
  |> Ok
}

type Param =
  #(infra.LatexDelimiterPair, List(LatexDelimiterPair))
//  prescribed_start/end        allowed_start/end

type InnerParam =
  #(List(String), String, List(String), String)

pub const name = "normalize_begin_end_align"
fn desugarer_blame(line_no: Int) {bl.Des([], name, line_no)}

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// adds delimiters around \\begin{align} and
/// \\end{align} if not already present
pub fn constructor(param: Param) -> Desugarer {
  Desugarer(
    name: name,
    stringified_param: option.Some(ins(param)),
    stringified_outside: option.None,
    transform: case param_to_inner_param(param) {
      Error(error) -> fn(_) { Error(error) }
      Ok(inner) -> transform_factory(inner)
    },
  )
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
fn assertive_tests_data() -> List(infra.AssertiveTestData(Param)) {
  [
    infra.AssertiveTestData(
      param: #(DoubleDollar, [DoubleDollar]),
      source:   "
                <> root
                  <>
                    \"Some text\"
                    \"\\begin{align}\"
                    \"x = 1\"
                    \"\\end{align}\"
                    \"More text\"
                ",
      expected: "
                <> root
                  <>
                    \"Some text\"
                    \"$$\"
                    \"\\begin{align}\"
                    \"x = 1\"
                    \"\\end{align}\"
                    \"$$\"
                    \"More text\"
                ",
    ),
    infra.AssertiveTestData(
      param: #(DoubleDollar, [DoubleDollar]),
      source:   "
                <> root
                  <>
                    \"Some text\"
                    \"\\begin{align*}\"
                    \"x = 1\"
                    \"\\end{align*}\"
                    \"More text\"
                ",
      expected: "
                <> root
                  <>
                    \"Some text\"
                    \"$$\"
                    \"\\begin{align*}\"
                    \"x = 1\"
                    \"\\end{align*}\"
                    \"$$\"
                    \"More text\"
                ",
    ),
    infra.AssertiveTestData(
      param: #(DoubleDollar, [DoubleDollar]),
      source:   "
                <> root
                  <>
                    \"Some text\"
                    \"$$ \"
                    \"\\begin{align}\"
                    \"x = 1\"
                    \"\\end{align}\"
                    \" $$\"
                    \"More text\"
                ",
      expected: "
                <> root
                  <>
                    \"Some text\"
                    \"$$\"
                    \"\\begin{align}\"
                    \"x = 1\"
                    \"\\end{align}\"
                    \"$$\"
                    \"More text\"
                ",
    ),
    infra.AssertiveTestData(
      param: #(DoubleDollar, [DoubleDollar]),
      source:   "
                <> root
                  <>
                    \"Some text\"
                    \"$$\\begin{align*}\"
                    \"x = 1\"
                    \"\\end{align*}$$\"
                    \"More text\"
                ",
      expected: "
                <> root
                  <>
                    \"Some text\"
                    \"$$\"
                    \"\\begin{align*}\"
                    \"x = 1\"
                    \"\\end{align*}\"
                    \"$$\"
                    \"More text\"
                ",
    ),
    infra.AssertiveTestData(
      param: #(DoubleDollar, [DoubleDollar]),
      source:   "
                <> root
                  <>
                    \"Some text\"
                    \"$$\"
                    \"\"
                    \"\"
                    \"\\begin{align*}\"
                    \"x = 1\"
                    \"\\end{align}\"
                    \"\"
                    \"\"
                    \"$$\"
                    \"More text\"
                ",
      expected: "
                <> root
                  <>
                    \"Some text\"
                    \"$$\"
                    \"\\begin{align*}\"
                    \"x = 1\"
                    \"\\end{align}\"
                    \"$$\"
                    \"More text\"
                ",
    ),
    infra.AssertiveTestData(
      param: #(DoubleDollar, [DoubleDollar]),
      source:   "
                <> root
                  <>
                    \"Some text\"
                    \"\\begin{align*}\"
                    \"\\begin{align}\"
                    \"\\end{align*}$$\"
                    \"More text\"
                ",
      expected: "
                <> root
                  <>
                    \"Some text\"
                    \"$$\"
                    \"\\begin{align*}\"
                    \"$$\"
                    \"\\begin{align}\"
                    \"\\end{align*}\"
                    \"$$\"
                    \"More text\"
                ",
    ),
    infra.AssertiveTestData(
      param: #(DoubleDollar, [DoubleDollar]),
      source:   "
                <> root
                  <>
                    \"A\"
                    \"B\"
                    \"\\begin{align}\\end{align}\"
                    \"C\"
                    \"D\"
                    \"\\begin{align}\\end{align}\"
                    \"E\"
                    \"F\"
                    \"\\begin{align}\\end{align}\"
                    \"G\"
                    \"H\"
                ",
      expected: "
                <> root
                  <>
                    \"A\"
                    \"B\"
                    \"$$\"
                    \"\\begin{align}\\end{align}\"
                    \"$$\"
                    \"C\"
                    \"D\"
                    \"$$\"
                    \"\\begin{align}\\end{align}\"
                    \"$$\"
                    \"E\"
                    \"F\"
                    \"$$\"
                    \"\\begin{align}\\end{align}\"
                    \"$$\"
                    \"G\"
                    \"H\"
                ",
    ),
  ]
}

pub fn assertive_tests() {
  infra.assertive_test_collection_from_data(
    name,
    assertive_tests_data(),
    constructor,
  )
}
