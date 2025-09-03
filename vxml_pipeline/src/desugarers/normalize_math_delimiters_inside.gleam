import gleam/list
import gleam/option
import gleam/string.{inspect as ins}
import infrastructure.{type Desugarer, Desugarer, type DesugarerTransform, type DesugaringError, DesugaringError, type LatexDelimiterPair} as infra
import nodemaps_2_desugarer_transforms as n2t
import vxml.{type VXML, T, V, TextLine}

fn remove_first_prefix_found(c: String, prefixes: List(String)) -> String {
  case prefixes {
    [] -> c
    [first, ..rest] -> case string.starts_with(c, first) {
      True -> string.drop_start(c, string.length(first))
      False -> remove_first_prefix_found(c, rest)
    }
  }
}

fn remove_first_suffix_found(c: String, suffixes: List(String)) -> String {
  case suffixes {
    [] -> c
    [first, ..rest] -> case string.ends_with(c, first) {
      True -> string.drop_end(c, string.length(first))
      False -> remove_first_suffix_found(c, rest)
    }
  }
}

fn normalize_t(
  t: VXML,
  inner: InnerParam,
) -> VXML {
  let assert T(blame, lines) = t
  let lines = infra.lines_trim_start(lines)
  let assert [first, ..rest] = lines
  let lines = [
    TextLine(..first, content: inner.2 <> remove_first_prefix_found(first.content, inner.0)),
    ..rest
  ]
  let lines = infra.reversed_lines_trim_end(lines |> list.reverse)
  let assert [first, ..rest] = lines
  let lines = [
    TextLine(..first, content: remove_first_suffix_found(first.content, inner.1) <> inner.3),
    ..rest
  ]
  let lines = lines |> list.reverse
  T(blame, lines)
}

fn nodemap(
  node: VXML,
  inner: InnerParam,
) -> Result(VXML, DesugaringError) {
  case node {
    V(_, tag, _, children) if tag == inner.4 -> case children {
      [T(_, _) as t] -> Ok(V(..node, children: [normalize_t(t, inner)]))
      _ -> Error(DesugaringError(node.blame, "expecting unique text child in target tag"))
    }
    _ -> Ok(node)
  }
}

fn nodemap_factory(inner: InnerParam) -> n2t.OneToOneNodeMap {
  nodemap(_, inner)
}

fn transform_factory(inner: InnerParam) -> DesugarerTransform {
  n2t.one_to_one_nodemap_2_desugarer_transform(nodemap_factory(inner))
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  let #(left_target, right_target) =
    infra.opening_and_closing_string_for_pair(param.1)
  let #(left_delims, right_delims) =
    infra.latex_strippable_delimiter_pairs()
    |> list.map(infra.opening_and_closing_string_for_pair)
    |> list.unzip
  let left_delims = list.filter(left_delims, fn(c) {c != left_target })
  let right_delims = list.filter(right_delims, fn(c) {c != right_target })
  Ok(#(
    left_delims,    // inner.0
    right_delims,   // inner.1
    left_target,    // inner.2
    right_target,   // inner.3
    param.0,        // inner.4
  ))
}

type Param =
  #(String,     LatexDelimiterPair)
//  ↖           ↖
//  tag         normalizing delimiter
//  to target   pair

type InnerParam =
  #(List(String),     List(String),      String,     String,       String)
//  ↖                 ↖                  ↖           ↖             ↖
//  left delimiters   right delimiters   left        right         tag
//  to remove         to remove          delimiter   delimiter     to target
//                                       to use      to use

pub const name = "normalize_math_delimiters_inside"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// adds flexiblilty to user's custom
/// mathblock element
/// ```
/// |> Mathblock
///     math
/// ```
/// should be same as
/// ```
/// |> Mathblock
///     $$math$$
/// ```
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
      param: #("MathBlock", infra.DoubleDollar),
      source:   "
                <> MathBlock
                  <>
                    \"x\"
                ",
      expected: "
                <> MathBlock
                  <>
                    \"$$x$$\"
                ",
    ),
    infra.AssertiveTestData(
      param: #("MathBlock", infra.DoubleDollar),
      source:   "
                <> MathBlock
                  <>
                    \"\\[x\\]\"
                ",
      expected: "
                <> MathBlock
                  <>
                    \"$$x$$\"
                ",
    ),
  ]
}

pub fn assertive_tests() {
  infra.assertive_test_collection_from_data(name, assertive_tests_data(), constructor)
}
