import gleam/list
import gleam/option
import gleam/string.{inspect as ins}
import desugaring/core.{type Desugarer, Desugarer, type DesugarerTransform, type DesugaringError} as core
import desugaring/nodemaps_2_transform as n2t
import vxml.{type VXML, V}

fn nodemap(
  node: VXML,
  ancestors: List(VXML),
  inner: InnerParam,
) -> List(VXML) {
  case node {
    V(_, tag, _, children) if tag == inner.0 -> case list.any(inner.1, fn(b) {list.any(ancestors, fn(a) { core.is_v_and_tag_equals(a, b)})}) {
      True -> children
      False -> [node]
    }
    _ -> [node]
  }
}

fn nodemap_factory(inner: InnerParam) -> n2t.FancyOneToManyNoErrorNodemap {
  fn(
    vxml: VXML,
    ancestors: List(VXML),
    _: List(VXML),
    _: List(VXML),
    _: List(VXML),
  ) {
    nodemap(vxml, ancestors, inner)
  }
}

fn transform_factory(inner: InnerParam) -> DesugarerTransform {
  nodemap_factory(inner)
  |> n2t.fancy_one_to_many_no_error_nodemap_2_desugarer_transform()
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(param)
}

type Param = #(String,        List(String))
//             ↖              ↖
//             tag to         list of ancestor names
//             be unwrapped   that should cause tag to unwrap
type InnerParam = Param

pub const name = "unwrap_if_descendant_of"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// unwraps a given tag when it is the descendant of
/// one of a stipulated list of tags
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
fn assertive_tests_data() -> List(core.AssertiveTestData(Param)) {
  []
}

pub fn assertive_tests() {
  core.assertive_test_collection_from_data(name, assertive_tests_data(), constructor)
}
