import gleam/option.{None, Some}
import gleam/list
import gleam/string
import infrastructure.{type Desugarer, Desugarer, type DesugarerTransform, type DesugaringError} as infra
import nodemaps_2_desugarer_transforms as n2t
import vxml.{type VXML, type Line, Line, T, V}

// word joiner character
const word_joiner = "&#8288;"

fn edit_last_line(lines: List(Line)) -> List(Line) {
  case list.reverse(lines) {
    [] -> []
    [last, ..rest] -> {
      let content = last.content
      case content != "" && !string.ends_with(content, " ") {
        True -> [Line(..last, content: content <> word_joiner), ..rest]
        False -> [last, ..rest]
      }
    }
  }
  |> list.reverse
}

fn edit_first_line(lines: List(Line)) -> List(Line) {
  case lines {
    [] -> []
    [first, ..rest] -> {
      let content = first.content
      case content != "" && !string.starts_with(content, " ") {
        True -> [Line(..first, content: word_joiner <> content), ..rest]
        False -> [first, ..rest]
      }
    }
  }
}

fn nodemap(
  vxml: VXML,
  prev_siblings: List(VXML),
  next_siblings: List(VXML),
  inner: InnerParam,
) -> VXML {
  case vxml {
    T(blame, lines) -> {
      let prev = list.first(prev_siblings)
      let next = list.first(next_siblings)

      let lines = case prev {
        Ok(V(_, tag, _, _)) ->
          case list.contains(inner, tag) {
            True -> edit_first_line(lines)
            False -> lines
          }
        _ -> lines
      }

      let lines = case next {
        Ok(V(_, tag, _, _)) ->
          case list.contains(inner, tag) {
            True -> edit_last_line(lines)
            False -> lines
          }
        _ -> lines
      }

      T(blame, lines)
    }
    _ -> vxml
  }
}

fn nodemap_factory(inner: InnerParam) -> n2t.FancyOneToOneNoErrorNodemap {
  fn(v, _, p1, _, f) { nodemap(v, p1, f, inner) }
}

fn transform_factory(inner: InnerParam) -> DesugarerTransform {
  nodemap_factory(inner)
  |> n2t.fancy_one_to_one_no_error_nodemap_2_desugarer_transform
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(param)
}

pub type Param = List(String)
type InnerParam = Param

pub const name = "insert_word_joiner_into_adjacent_text_nodes"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// inserts word joiner character into text nodes
/// adjacent to specified tags if there is no whitespace
pub fn constructor(param: Param) -> Desugarer {
  Desugarer(
    name: name,
    stringified_param: Some(string.inspect(param)),
    stringified_outside: None,
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
      param: ["Math"],
      source: "
                <> div
                  <>
                    'a'
                  <> Math
                  <>
                    'b'
              ",
      expected: "
                <> div
                  <>
                    'a&#8288;'
                  <> Math
                  <>
                    '&#8288;b'
                ",
    ),
    infra.AssertiveTestData(
      param: ["Math"],
      source: "
                <> div
                  <>
                    'a '
                  <> Math
                  <>
                    ' b'
              ",
      expected: "
                <> div
                  <>
                    'a '
                  <> Math
                  <>
                    ' b'
                ",
    ),
    infra.AssertiveTestData(
      param: ["Math"],
      source: "
                <> div
                  <>
                    'a'
                    ''
                  <> Math
                  <>
                    ''
                    'b'
              ",
      expected: "
                <> div
                  <>
                    'a'
                    ''
                  <> Math
                  <>
                    ''
                    'b'
                ",
    ),
  ]
}

pub fn assertive_tests() {
  infra.assertive_test_collection_from_data(name, assertive_tests_data(), constructor)
}
