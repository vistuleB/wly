import gleam/option
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
  type VXML,
  type Attr,
  Attr,
  V,
}
import blame as bl

fn nodemap(
  vxml: VXML,
  inner: InnerParam,
) -> #(VXML, TrafficLight) {
  case vxml {
    V(_, tag, attrs, _) if tag == inner.0 ->
      #(V(..vxml, attrs: [inner.1, ..attrs]), inner.2)
    _ -> #(vxml, Continue)
  }
}

fn nodemap_factory(inner: InnerParam) -> n2t.EarlyReturnOneToOneNoErrorNodeMap {
  nodemap(_, inner)
}

fn transform_factory(inner: InnerParam) -> DesugarerTransform {
  nodemap_factory(inner)
  |> n2t.early_return_one_to_one_no_error_nodemap_2_desugarer_transform
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  #(
    param.0,
    Attr(desugarer_blame(44), "_", param.1 <> " ::++" <> param.1),
    param.2,
  )
  |> Ok
}

type Param = #(String, String,  TrafficLight)
//             ↖       ↖        ↖
//             tag     counter  pursue-nested-or-not
type InnerParam = #(String, Attr, TrafficLight)
fn desugarer_blame(line_no: Int) { bl.Des([], name, line_no) }

pub const name = "prepend_counter_incrementing_attribute"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// For each #(tag, counter_name, traffic_light)
/// tuple in the parameter list, this desugarer adds
/// an attr of the form
/// ```
/// _=counter_name ::++counter_name
/// ```
/// to each node of tag 'tag', where the key is a
/// period '.' and the value is the string
/// '<counter_name> ::++<counter_name>'. As counters
/// are evaluated and substitued also inside of
/// key-value pairs, adding this key-value pair
/// causes the counter <counter_name> to increment at
/// each occurrence of a node of tag 'tag'.
pub fn constructor(
  param: Param,
) -> Desugarer {
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
      param: #("Chapter", "ChapterCounter", GoBack),
      source:   "
                  <> root
                    <> Chapter
                      title=Introduction
                      <>
                        \"Chapter content\"
                      <> Chapter
                        title=Should not change
                    <> Chapter
                      title=Advanced Topics
                      <>
                        \"More content\"
                      <> Chapter
                        title=Should not change
                    <> OtherElement
                      <>
                        \"Should not change\"
                ",
      expected: "
                  <> root
                    <> Chapter
                      _=ChapterCounter ::++ChapterCounter
                      title=Introduction
                      <>
                        \"Chapter content\"
                      <> Chapter
                        title=Should not change
                    <> Chapter
                      _=ChapterCounter ::++ChapterCounter
                      title=Advanced Topics
                      <>
                        \"More content\"
                      <> Chapter
                        title=Should not change
                    <> OtherElement
                      <>
                        \"Should not change\"
                ",
    ),
    infra.AssertiveTestData(
      param: #("Sub", "SubCounter", Continue),
      source:   "
                  <> root
                    <> Sub
                      title=Overview
                      <>
                        \"Sub content\"
                      <> Sub
                        title=Details
                        <>
                          \"More sub content\"
                    <> Chapter
                      title=Should not change
                      <>
                        \"Chapter content\"
                ",
      expected: "
                  <> root
                    <> Sub
                      _=SubCounter ::++SubCounter
                      title=Overview
                      <>
                        \"Sub content\"
                      <> Sub
                        _=SubCounter ::++SubCounter
                        title=Details
                        <>
                          \"More sub content\"
                    <> Chapter
                      title=Should not change
                      <>
                        \"Chapter content\"
                ",
    ),
    infra.AssertiveTestData(
      param: #("Exercise", "ExerciseCounter", Continue),
      source:   "
                  <> root
                    <> Exercise
                      number=1
                      <> Exercise
                        number=nested
                        <>
                          \"Nested exercise\"
                      <>
                        \"Exercise content\"
                    <> Section
                      <>
                        \"Section content\"
                ",
      expected: "
                  <> root
                    <> Exercise
                      _=ExerciseCounter ::++ExerciseCounter
                      number=1
                      <> Exercise
                        _=ExerciseCounter ::++ExerciseCounter
                        number=nested
                        <>
                          \"Nested exercise\"
                      <>
                        \"Exercise content\"
                    <> Section
                      <>
                        \"Section content\"
                ",
    ),
  ]
}

pub fn assertive_tests() {
  infra.assertive_test_collection_from_data(name, assertive_tests_data(), constructor)
}
