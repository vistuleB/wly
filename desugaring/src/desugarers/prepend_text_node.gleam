import gleam/option
import gleam/list
import gleam/string.{inspect as ins}
import infrastructure.{type Desugarer, Desugarer, type DesugarerTransform, type DesugaringError, type TrafficLight, Continue, GoBack} as infra
import nodemaps_2_desugarer_transforms as n2t
import vxml.{ type VXML, Line, T, V }
import blame as bl

fn nodemap(
  vxml: VXML,
  inner: InnerParam,
) -> #(VXML, TrafficLight) {
  case vxml {
    V(_, tag, _, children) if tag == inner.0 -> #(
      V(..vxml, children: [inner.1, ..children]),
      GoBack,
    )
    _ -> #(vxml, Continue)
  }
}

fn nodemap_factory(inner: InnerParam) -> n2t.EarlyReturnOneToOneNoErrorNodeMap {
  nodemap(_, inner)
}

fn transform_factory(inner: InnerParam) -> DesugarerTransform {
  nodemap_factory(inner)
  |> n2t.early_return_one_to_one_no_error_nodemap_2_desugarer_transform()
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  #(
    param.0,
    T(
      desugarer_blame(35),
      param.1
      |> string.split("\n")
      |> list.map(Line(desugarer_blame(38), _))
    )
  )
  |> Ok
}

type Param = #(String, String)
//             ↖       ↖
//             tag     text
type InnerParam = #(String, VXML)

pub const name = "prepend_text_node"
fn desugarer_blame(line_no: Int) { bl.Des([], name, line_no) }

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// Given arguments
/// ```
/// tag, text
/// ```
/// prepends a text node wit content 'text' to nodes
/// of tag 'tag'. The newline character can be
/// included in 'text', which will be translated to
/// >1 Line.
///
/// Early-returns from nodes of tag 'tag'.
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
      param: #("ChapterTitle", "::øøChapterCounter. "),
      source:   "
                  <> root
                    <> ChapterTitle
                      <>
                        \"Einleitung\"
                    <> ChapterTitle
                      <>
                        \"Advanced Topics\"
                        \"More content\"
                    <> OtherElement
                      <>
                        \"Should not change\"
                ",
      expected: "
                  <> root
                    <> ChapterTitle
                      <>
                        \"::øøChapterCounter. \"
                      <>
                        \"Einleitung\"
                    <> ChapterTitle
                      <>
                        \"::øøChapterCounter. \"
                      <>
                        \"Advanced Topics\"
                        \"More content\"
                    <> OtherElement
                      <>
                        \"Should not change\"
                ",
    ),
    infra.AssertiveTestData(
      param: #("SubTitle", "::øøChapterCounter.::øøSubCounter "),
      source:   "
                  <> root
                    <> SubTitle
                      <>
                        \"Overview\"
                    <> SubTitle
                      <>
                        \"Details\"
                        \"Additional info\"
                    <> ChapterTitle
                      <>
                        \"Should not change\"
                ",
      expected: "
                  <> root
                    <> SubTitle
                      <>
                        \"::øøChapterCounter.::øøSubCounter \"
                      <>
                        \"Overview\"
                    <> SubTitle
                      <>
                        \"::øøChapterCounter.::øøSubCounter \"
                      <>
                        \"Details\"
                        \"Additional info\"
                    <> ChapterTitle
                      <>
                        \"Should not change\"
                ",
    ),
  ]
}

pub fn assertive_tests() {
  infra.assertive_test_collection_from_data(name, assertive_tests_data(), constructor)
}
