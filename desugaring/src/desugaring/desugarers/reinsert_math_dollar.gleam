import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError, DesugaringError,
}
import desugaring/nodemaps_2_transform as n2t
import gleam/dict
import gleam/int
import gleam/list
import gleam/result
import vxml.{type VXML, Line, T, V}
import vxml/blame.{type Blame}

pub const name = "reinsert_math_dollar"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Reinserts dollar delimiters into Math and MathBlock
/// elements having exactly one child.
pub fn constructor() -> Desugarer {
  authoring.no_param_desugarer(
    name: name,
    transform: inner_param_to_transform(Nil),
  )
}

type InnerParam =
  Nil

fn inner_param_to_transform(inner: InnerParam) -> DesugarerTransform {
  nodemap_factory(inner)
  |> n2t.one_to_one_nodemap_2_desugarer_transform
}

fn nodemap_factory(_: InnerParam) -> n2t.OneToOneNodemap {
  nodemap
}

fn nodemap(vxml: VXML) -> Result(VXML, DesugaringError) {
  let math_delimiters = dict.from_list([#("Math", "$"), #("MathBlock", "$$")])

  case vxml {
    V(blame, tag, _, children) ->
      case dict.get(math_delimiters, tag) {
        Ok(delimiter) -> {
          use children <- result.try(update_children(
            children,
            delimiter,
            tag,
            blame,
          ))
          Ok(V(..vxml, children: children))
        }
        Error(_) -> Ok(vxml)
      }
    _ -> Ok(vxml)
  }
}

fn update_children(
  vxmls: List(VXML),
  delimiter: String,
  tag: String,
  blame: Blame,
) -> Result(List(VXML), DesugaringError) {
  case vxmls {
    [only_child] -> Ok(insert_delimiter(only_child, delimiter, Both))
    _ ->
      Error(DesugaringError(
        blame,
        "expected exactly one child in '"
          <> tag
          <> "', found "
          <> int.to_string(list.length(vxmls)),
      ))
  }
}

fn insert_delimiter(
  vxml: VXML,
  delimiter: String,
  position: DelimiterPosition,
) -> List(VXML) {
  case vxml {
    T(blame, lines) ->
      case position {
        First -> [T(blame, [Line(blame, delimiter), ..lines])]
        Last -> [T(blame, list.append(lines, [Line(blame, delimiter)]))]
        Both -> [
          T(
            blame,
            list.flatten([
              [Line(blame, delimiter)],
              lines,
              [Line(blame, delimiter)],
            ]),
          ),
        ]
      }
    V(blame, _, _, _) ->
      case position {
        First -> [T(blame, [Line(blame, delimiter)]), vxml]
        Last -> [vxml, T(blame, [Line(blame, delimiter)])]
        Both -> [
          T(blame, [Line(blame, delimiter)]),
          vxml,
          T(blame, [Line(blame, delimiter)]),
        ]
      }
  }
}

type DelimiterPosition {
  First
  Last
  Both
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊

fn assertive_tests_data() -> List(core.AssertiveTestDataNoParam) {
  [
    core.AssertiveTestDataNoParam(
      source: "
                <> root
                  <> Math
                    <>
                      'x + y'
                  <> MathBlock
                    <> Equation
                ",
      expected: "
                <> root
                  <> Math
                    <>
                      '$'
                      'x + y'
                      '$'
                  <> MathBlock
                    <>
                      '$$'
                    <> Equation
                    <>
                      '$$'
                ",
    ),
  ]
}

pub fn assertive_tests() {
  core.assertive_test_collection_from_data_no_param(
    name,
    assertive_tests_data(),
    constructor,
  )
}
