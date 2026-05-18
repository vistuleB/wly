import gleam/function
import gleam/list
import gleam/string.{inspect as ins}
import gleam/option.{type Option, Some, None}
import infrastructure.{type Desugarer, Desugarer, type DesugarerTransform, type DesugaringError} as infra
import nodemaps_2_desugarer_transforms as n2t
import vxml.{type VXML}

fn v_before(
  vxml: VXML,
  state: State,
  inner: InnerParam,
) -> #(Option(VXML), State, infra.TrafficLight) {
  assert !state
  case inner(vxml) {
    True -> #(Some(vxml), True, infra.GoBack)
    False -> #(Some(vxml), False, infra.Continue)
  }
}

fn v_after(
  vxml: VXML,
  original_state: State,
  children_states: List(State),
) -> #(Option(VXML), State) {
  assert !original_state
  case list.any(children_states, function.identity) {
    True -> #(Some(vxml), True)
    False -> #(None, False)
  }
}

fn t_transform(
  vxml: VXML,
  state: State,
  inner: InnerParam,
) -> #(Option(VXML), State) {
  assert !state
  case inner(vxml) {
    True -> #(Some(vxml), True)
    False -> #(None, False)
  }
}

fn nodemap_factory(inner: InnerParam) -> n2t.EarlyReturnOneToOptionNoErrorBeforeAndAfterV2StatefulNodemap(State) {
  n2t.EarlyReturnOneToOptionNoErrorBeforeAndAfterV2StatefulNodemap(
    fn(v, s) { v_before(v, s, inner) }, 
    v_after, 
    fn(v, s) { t_transform(v, s, inner) }, 
  )
}

fn transform_factory(inner: InnerParam) -> DesugarerTransform {
  nodemap_factory(inner)
  |> n2t.early_return_one_to_option_no_error_before_and_after_v2_stateful_nodemap_2_desugarer_transform(False)
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(param)
}

type State = Bool

type Param = fn(VXML) -> Bool
//           ↖
//           a node is saved
//           iff it or one of its
//           ancestors fulfills
//           this condition
type InnerParam = Param

pub const name = "delete_outside_subtrees_v2"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// removes nodes that are outside subtrees matching
/// the predicate function
pub fn constructor(param: Param) -> Desugarer {
  Desugarer(
    name: name,
    stringified_param: option.Some(ins(param)),
    stringified_outside: option.None,
    transform: case param_to_inner_param(param) {
      Ok(inner) -> transform_factory(inner)
      Error(error) -> fn(_) { Error(error) }
    }
  )
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
fn assertive_tests_data() -> List(infra.AssertiveTestData(Param)) {
  [
    infra.AssertiveTestData(
      param: infra.is_v_and_tag_equals(_, "keep_this"),
      source:   "
                <> R
                  <>
                    'hello world'
                  <> blabla
                  <> keep_this
                    <>
                      'hello world'
                ",
      expected: "
                <> R
                  <> keep_this
                    <>
                      'hello world'
                ",
    ),
  ]
}

pub fn assertive_tests() {
  infra.assertive_test_collection_from_data(name, assertive_tests_data(), constructor)
}
