import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
  type TrafficLight, Continue, GoBack,
}
import desugaring/nodemaps_2_transform as n2t
import gleam/list
import gleam/string
import vxml.{type VXML, Line, T, V}

pub const name = "prepend_text_node"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Prepends a text node to every matching element and
/// skips traversal of its descendants.
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
    // Target tag.
    String,
    // Text to prepend.
    String,
  )

type InnerParam =
  #(String, VXML)

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  #(
    param.0,
    T(
      desugarer_blame(43),
      param.1
        |> string.split("\n")
        |> list.map(Line(desugarer_blame(46), _)),
    ),
  )
  |> Ok
}

fn inner_param_to_transform(inner: InnerParam) -> DesugarerTransform {
  let nodemap: n2t.EarlyReturnOneToOneNoErrorNodemap = nodemap(_, inner)
  nodemap
  |> n2t.early_return_one_to_one_no_error_nodemap_2_desugarer_transform()
}

fn nodemap(vxml: VXML, inner: InnerParam) -> #(VXML, TrafficLight) {
  case vxml {
    V(_, tag, _, children) if tag == inner.0 -> #(
      V(..vxml, children: [inner.1, ..children]),
      GoBack,
    )
    _ -> #(vxml, Continue)
  }
}

fn desugarer_blame(line_no: Int) {
  authoring.blame(name, line_no)
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊

fn assertive_tests_data() -> List(core.AssertiveTestData(Param)) {
  [
    core.AssertiveTestData(
      param: #("ChapterTitle", "::øøChapterCounter. "),
      source: "
                  <> root
                    <> ChapterTitle
                      <>
                        'Einleitung'
                    <> ChapterTitle
                      <>
                        'Advanced Topics'
                        'More content'
                    <> OtherElement
                      <>
                        'Should not change'
                ",
      expected: "
                  <> root
                    <> ChapterTitle
                      <>
                        '::øøChapterCounter. '
                      <>
                        'Einleitung'
                    <> ChapterTitle
                      <>
                        '::øøChapterCounter. '
                      <>
                        'Advanced Topics'
                        'More content'
                    <> OtherElement
                      <>
                        'Should not change'
                ",
    ),
    core.AssertiveTestData(
      param: #("SubTitle", "::øøChapterCounter.::øøSubCounter "),
      source: "
                  <> root
                    <> SubTitle
                      <>
                        'Overview'
                    <> SubTitle
                      <>
                        'Details'
                        'Additional info'
                    <> ChapterTitle
                      <>
                        'Should not change'
                ",
      expected: "
                  <> root
                    <> SubTitle
                      <>
                        '::øøChapterCounter.::øøSubCounter '
                      <>
                        'Overview'
                    <> SubTitle
                      <>
                        '::øøChapterCounter.::øøSubCounter '
                      <>
                        'Details'
                        'Additional info'
                    <> ChapterTitle
                      <>
                        'Should not change'
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
