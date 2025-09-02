import gleam/option
import gleam/string.{inspect as ins}
import infrastructure.{type Desugarer, Desugarer, type DesugarerTransform, type DesugaringError} as infra
import nodemaps_2_desugarer_transforms as n2t

fn nodemap_factory(
  inner: InnerParam
) -> n2t.OneToOneNoErrorNodeMap {
  infra.find_replace_if_t(_, inner.0, inner.1)
}

fn transform_factory(inner: InnerParam, outside: List(String)) -> DesugarerTransform {
  nodemap_factory(inner)
  |> n2t.one_to_one_no_error_nodemap_2_desugarer_transform_with_forbidden(outside)
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(param)
}

type Param = #(String, String)
//             ↖       ↖
//             from    to
type InnerParam = Param

pub const name = "find_replace__outside"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// find-and-replace a string with another string
/// in text nodes, while avoiding subtrees rooted at
/// tags appearing in the third argument to the
/// desugarer
pub fn constructor(param: Param, outside: List(String)) -> Desugarer {
  Desugarer(
    name: name,
    stringified_param: option.Some(ins(param)),
    stringified_outside: option.Some(ins(outside)),
    transform: case param_to_inner_param(param) {
      Error(error) -> fn(_) { Error(error) }
      Ok(inner) -> transform_factory(inner, outside)
    },
  )
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
fn assertive_tests_data() -> List(infra.AssertiveTestDataWithOutside(Param)) {
  [
    infra.AssertiveTestDataWithOutside(
      param: #("from", "to"),
      outside: ["keep_out"],
      source:   "
                <> root
                  <> A
                    <> B
                      <>
                        \"from a thing\"
                        \"to a thing\"
                      <> keep_out
                        <>
                          \"from a thing\"
                          \"to a thing\"
                    <> keep_out
                      <> B
                        <>
                          \"from a thing\"
                          \"to a thing\"
                ",
      expected: "
                <> root
                  <> A
                    <> B
                      <>
                        \"to a thing\"
                        \"to a thing\"
                      <> keep_out
                        <>
                          \"from a thing\"
                          \"to a thing\"
                    <> keep_out
                      <> B
                        <>
                          \"from a thing\"
                          \"to a thing\"
                ",
    )
  ]
}

pub fn assertive_tests() {
  infra.assertive_test_collection_from_data_with_outside(name, assertive_tests_data(), constructor)
}
