import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
  type TrafficLight, Continue, GoBack,
}
import desugaring/nodemaps_2_transform as n2t
import vxml.{type VXML, V}

pub const name = "unwrap__outside"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Unwraps matching elements outside configured subtrees.
pub fn constructor(param: Param, outside: List(String)) -> Desugarer {
  authoring.desugarer_with_outside(
    name: name,
    param: param,
    outside: outside,
    prepare: param_to_inner_param,
    transform: inner_param_to_transform,
  )
}

fn nodemap(node: VXML, inner: InnerParam) -> #(List(VXML), TrafficLight) {
  case node {
    V(_, tag, _, children) if tag == inner -> #(children, GoBack)
    _ -> #([node], Continue)
  }
}

fn inner_param_to_transform(
  inner: InnerParam,
  outside: List(String),
) -> DesugarerTransform {
  let nodemap: n2t.EarlyReturnOneToManyNoErrorNodemap = nodemap(_, inner)
  nodemap
  |> n2t.early_return_one_to_many_no_error_nodemap_2_desugarer_transform_with_forbidden(
    outside,
  )
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(param)
}

type Param =
  String

type InnerParam =
  Param

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
fn assertive_tests_data() -> List(core.AssertiveTestDataWithOutside(Param)) {
  []
}

pub fn assertive_tests() {
  core.assertive_test_collection_from_data_with_outside(
    name,
    assertive_tests_data(),
    constructor,
  )
}
