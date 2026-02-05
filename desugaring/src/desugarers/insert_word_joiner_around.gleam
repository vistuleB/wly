import gleam/option.{type Option, None, Some}
import gleam/list
import gleam/string
import vxml.{type VXML, V, T, Line}
import infrastructure.{type Desugarer, Desugarer} as infra
import desugarers/insert_before_after_if
import blame

fn condition(
  prev: Option(VXML),
  child: VXML,
  next: Option(VXML),
  tags: List(String),
) -> #(Bool, Bool) {
  case child {
    V(_, tag, _, _) -> {
      case list.contains(tags, tag) {
        True -> {
          let do_bef = case prev {
            Some(node) -> {
              case node {
                T(_, lines) -> {
                  case list.last(lines) {
                    Ok(line) -> {
                      let content = line.content
                      content != "" && !string.ends_with(content, " ")
                    }
                    Error(Nil) -> False
                  }
                }
                V(..) -> True
              }
            }
            None -> False
          }

          let do_aft = case next {
            Some(node) -> {
              case node {
                T(_, lines) -> {
                  case list.first(lines) {
                    Ok(line) -> {
                      let content = line.content
                      content != "" && !string.starts_with(content, " ")
                    }
                    Error(Nil) -> False
                  }
                }
                V(..) -> True
              }
            }
            None -> False
          }
          #(do_bef, do_aft)
        }
        False -> #(False, False)
      }
    }
    _ -> #(False, False)
  }
}

pub type Param =
  List(String)

pub const name = "insert_word_joiner_around"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// inserts word joiner characters around specified
/// tags when they are adjacent to non-space text
pub fn constructor(param: Param) -> Desugarer {
  let b = blame.Des([], name, 0)
  let word_joiner = "&#8288;"
  let wj_node = T(b, [Line(b, word_joiner)])

  let cond = fn(p, c, n) { condition(p, c, n, param) }

  let base_desugarer =
    insert_before_after_if.constructor(#(cond, wj_node, wj_node))

  Desugarer(
    ..base_desugarer,
    name: name,
    stringified_param: Some(string.inspect(param)),
  )
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊

fn assertive_tests_data() -> List(infra.AssertiveTestData(Param)) {
  let wj = "&#8288;"
  [
    infra.AssertiveTestData(
      param: ["wj"],
      source: "
              <> div
                <>
                  'a'
                <> wj
                <>
                  'b'
              ",
      expected: "
                <> div
                  <>
                    'a'
                  <>
                    '" <> wj <> "'
                  <> wj
                  <>
                    '" <> wj <> "'
                  <>
                    'b'
                ",
    ),
    infra.AssertiveTestData(
      param: ["wj"],
      source: "
              <> div
                <>
                  'a '
                <> wj
                <>
                  ' b'
              ",
      expected: "
                <> div
                  <>
                    'a '
                  <> wj
                  <>
                    ' b'
                ",
    ),
    infra.AssertiveTestData(
      param: ["wj"],
      source: "
              <> div
                <> span
                  <>
                    'a'
                <> wj
                <> span
                  <>
                    'b'
              ",
      expected: "
                <> div
                  <> span
                    <>
                      'a'
                  <>
                    '" <> wj <> "'
                  <> wj
                  <>
                    '" <> wj <> "'
                  <> span
                    <>
                      'b'
                ",
    ),
  ]
}

pub fn assertive_tests() {
  infra.assertive_test_collection_from_data(name, assertive_tests_data(), constructor)
}
