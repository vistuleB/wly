import gleam/option
import gleam/list
import gleam/string.{inspect as ins}
import infrastructure.{
  type Desugarer,
  type DesugarerTransform,
  type DesugaringError,
  type TrafficLight,
  Desugarer,
  Continue,
  GoBack,
} as infra
import nodemaps_2_desugarer_transforms as n2t
import vxml.{
  type Attr,
  type VXML,
  Attr,
  V,
}

fn map_attr(
  attr: Attr,
  inner: InnerParam,
) -> Attr {
  case attr.key {
    "handle" -> {
      case attr.value |> string.split_once(" ") {
        Ok(#(_, handle_value)) -> {
          assert string.trim(handle_value) != ""
          attr
        }
        _ ->
          Attr(..attr, value: attr.value <> " " <> inner.1)
      }
    }
    _ -> attr
  }
}

fn nodemap(
  vxml: VXML,
  inner: InnerParam,
) -> #(VXML, TrafficLight) {
  case vxml {
    V(_, tag, attrs, _) if tag == inner.0 ->
      #(
        V(..vxml, attrs: list.map(attrs, map_attr(_, inner))),
        inner.2,
      )
    _ -> #(vxml, Continue)
  }
}

fn nodemap_factory(inner: InnerParam) -> n2t.EarlyReturnOneToOneNoErrorNodeMap {
  nodemap(_, inner)
}

fn transform_factory(
  inner: InnerParam,
) -> DesugarerTransform {
  nodemap_factory(inner)
  |> n2t.early_return_one_to_one_no_error_nodemap_2_desugarer_transform
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(param)
}

type Param = #(String, String, TrafficLight)
//             ↖       ↖       ↖
//             tag     value   return-early-or-not
type InnerParam = Param

pub const name = "set_handle_value"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// add a specific key-value pair to all tags of a
/// given name and possibl early-return after
/// attr is added, depending on TrafficLight
/// instructions
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
      param: #("Chapter", "::øøChapterCounter", GoBack),
      source:   "
                  <> root
                    <> Chapter
                      handle=complexity-theory:page
                      <>
                        \"Chapter content\"
                    <> Chapter
                      handle=algorithms:intro some-existing-value
                      <>
                        \"More content\"
                    <> OtherElement
                      handle=should-not-change
                      <>
                        \"Should not change\"
                ",
      expected: "
                  <> root
                    <> Chapter
                      handle=complexity-theory:page ::øøChapterCounter
                      <>
                        \"Chapter content\"
                    <> Chapter
                      handle=algorithms:intro some-existing-value
                      <>
                        \"More content\"
                    <> OtherElement
                      handle=should-not-change
                      <>
                        \"Should not change\"
                ",
    ),
    infra.AssertiveTestData(
      param: #("Sub", "::øøChapterCounter.::øøSubCounter", GoBack),
      source:   "
                  <> root
                    <> Sub
                      handle=theorem:proof
                      <>
                        \"Sub content\"
                    <> Sub
                      handle=lemma:basic already-has-value
                      <>
                        \"More sub content\"
                    <> Chapter
                      handle=should-not-change
                      <>
                        \"Chapter content\"
                ",
      expected: "
                  <> root
                    <> Sub
                      handle=theorem:proof ::øøChapterCounter.::øøSubCounter
                      <>
                        \"Sub content\"
                    <> Sub
                      handle=lemma:basic already-has-value
                      <>
                        \"More sub content\"
                    <> Chapter
                      handle=should-not-change
                      <>
                        \"Chapter content\"
                ",
    ),
  ]
}

pub fn assertive_tests() {
  infra.assertive_test_collection_from_data(name, assertive_tests_data(), constructor)
}
