import gleam/option
import gleam/string.{inspect as ins}
import infrastructure.{
  type Desugarer,
  type DesugarerTransform,
  type DesugaringError,
  type TrafficLight,
  type FancyConditionFn,
  Continue,
  Desugarer,
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
  ancestors: List(VXML),
  previous_siblings_before_mapping: List(VXML),
  previous_siblings_after_mapping: List(VXML),
  following_siblings_before_mapping: List(VXML),
  inner: InnerParam,
) -> #(VXML, TrafficLight) {
  case vxml {
    V(_, tag, attrs, _) if tag == inner.0 ->{
      case inner.2(vxml, ancestors, previous_siblings_before_mapping, previous_siblings_after_mapping, following_siblings_before_mapping) {
        True -> #(V(..vxml, attrs: [inner.1, ..attrs]), inner.3)
        False -> #(vxml, Continue)
      }
    }
    _ -> #(vxml, Continue)
  }
}

fn nodemap_factory(inner: InnerParam) -> n2t.EarlyReturnFancyOneToOneNoErrorNodemap {
  fn(node, ancestors, previous_siblings_before_mapping, previous_siblings_after_mapping, following_siblings_before_mapping) {
    nodemap(node, ancestors, previous_siblings_before_mapping, previous_siblings_after_mapping, following_siblings_before_mapping, inner)
  }
}

fn transform_factory(inner: InnerParam) -> DesugarerTransform {
  nodemap_factory(inner)
  |> n2t.early_return_fancy_one_to_one_no_error_nodemap_2_desugarer_transform
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  #(
    param.0,
    Attr(desugarer_blame(51), "_", param.1 <> " ::++" <> param.1),
    param.2,
    param.3,
  )
  |> Ok
}

type Param = #(String, String, FancyConditionFn, TrafficLight)
//             ↖       ↖        ↖                ↖
//             tag     counter  condition        early return
type InnerParam = #(String, Attr, FancyConditionFn, TrafficLight)
fn desugarer_blame(line_no: Int) { bl.Des([], name, line_no) }

pub const name = "prepend_counter_incrementing_attribute"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// same as prepend_counter_incrementing_attribute
/// with a condition function

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
  []
}

pub fn assertive_tests() {
  infra.assertive_test_collection_from_data(name, assertive_tests_data(), constructor)
}
