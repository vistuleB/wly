import gleam/option
import gleam/string.{inspect as ins}
import desugaring/core.{type Desugarer, Desugarer, type DesugarerTransform, type DesugaringError} as core
import desugaring/nodemaps_2_transform as n2t

fn nodemap_factory(inner: InnerParam) -> n2t.OneToOneNoErrorNodemap {
  core.find_replace_if_t__batch(_, inner)
}

fn transform_factory(inner: InnerParam, outside: List(String)) -> DesugarerTransform {
  nodemap_factory(inner)
  |> n2t.one_to_one_no_error_nodemap_2_desugarer_transform_with_forbidden(outside)
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(param)
}

type Param = List(#(String, String))
//           ↖
//           from/to pairs
type InnerParam = Param

pub const name = "find_replace__batch__outside"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// find and replace strings with other strings
pub fn constructor(param: Param, outside: List(String)) -> Desugarer {
  Desugarer(
    name: name,
    stringified_param: option.Some(ins(param)),
    stringified_outside: option.None,
    transform: case param_to_inner_param(param) {
      Error(error) -> fn(_) { Error(error) }
      Ok(inner) -> transform_factory(inner, outside)
    },
  )
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
fn assertive_tests_data() -> List(core.AssertiveTestDataWithOutside(Param)) {
  [
    core.AssertiveTestDataWithOutside(
      param: [#("from", "to")],
      outside: ["keep_out"],
      source:   "
                <> root
                  <> A
                    <> B
                      <>
                        'from a thing'
                        'to a thing'
                      <> keep_out
                        <>
                          'from a thing'
                          'to a thing'
                    <> keep_out
                      <> B
                        <>
                          'from a thing'
                          'to a thing'
                ",
      expected: "
                <> root
                  <> A
                    <> B
                      <>
                        'to a thing'
                        'to a thing'
                      <> keep_out
                        <>
                          'from a thing'
                          'to a thing'
                    <> keep_out
                      <> B
                        <>
                          'from a thing'
                          'to a thing'
                ",
    )
  ]
}

pub fn assertive_tests() {
  core.assertive_test_collection_from_data_with_outside(name, assertive_tests_data(), constructor)
}
