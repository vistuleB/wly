import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
}
import desugaring/nodemaps_2_transform as n2t
import gleam/list
import vxml.{type VXML, T, V}

pub const name = "trim__batch"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Trims boundary whitespace from elements with configured tags.
pub fn constructor(param: Param) -> Desugarer {
  authoring.desugarer(
    name: name,
    param: param,
    prepare: param_to_inner_param,
    transform: inner_param_to_transform,
  )
}

fn nodemap(vxml: VXML, inner: InnerParam) -> VXML {
  case vxml {
    T(_, _) -> vxml
    V(_, tag, _, _) ->
      case list.contains(inner, tag) {
        True ->
          vxml
          |> core.v_trim_start
          |> core.v_trim_end
        False -> vxml
      }
  }
}

fn nodemap_factory(inner: InnerParam) -> n2t.OneToOneNoErrorNodemap {
  nodemap(_, inner)
}

fn inner_param_to_transform(inner: InnerParam) -> DesugarerTransform {
  nodemap_factory(inner)
  |> n2t.one_to_one_no_error_nodemap_2_desugarer_transform()
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(param)
}

type Param =
  List(String)

type InnerParam =
  Param

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
fn assertive_tests_data() -> List(core.AssertiveTestData(Param)) {
  [
    core.AssertiveTestData(
      param: ["A", "B"],
      source: "
                <> root
                  <> A
                    <>
                      '  a  '
                  <> B
                    <>
                      '  b  '
                  <> C
                    <>
                      '  c  '
                ",
      expected: "
                <> root
                  <> A
                    <>
                      'a'
                  <> B
                    <>
                      'b'
                  <> C
                    <>
                      '  c  '
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
