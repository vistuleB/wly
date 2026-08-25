import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError, Desugarer,
}
import desugaring/nodemaps_2_transform as n2t
import gleam/function
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string.{inspect as ins}
import vxml.{type VXML}

fn v_before(
  vxml: VXML,
  state: State,
  inner: InnerParam,
) -> #(Option(VXML), State, core.TrafficLight) {
  assert !state
  case inner(vxml) {
    True -> #(Some(vxml), True, core.GoBack)
    False -> #(Some(vxml), False, core.Continue)
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

fn nodemap_factory(
  inner: InnerParam,
) -> n2t.EarlyReturnOneToOptionEnterExitStatefulWithChildStatesNoErrorNodemap(
  State,
) {
  n2t.EarlyReturnOneToOptionEnterExitStatefulWithChildStatesNoErrorNodemap(
    fn(v, s) { v_before(v, s, inner) },
    v_after,
    fn(v, s) { t_transform(v, s, inner) },
  )
}

fn transform_factory(inner: InnerParam) -> DesugarerTransform {
  nodemap_factory(inner)
  |> n2t.early_return_one_to_option_enter_exit_stateful_with_child_states_no_error_nodemap_2_desugarer_transform(
    False,
  )
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(param)
}

type State =
  Bool

type Param =
  fn(VXML) -> Bool

//           ↖
//           a node is saved
//           iff it or one of its
//           ancestors fulfills
//           this condition
type InnerParam =
  Param

pub const name = "delete_outside_subtrees"

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
    },
  )
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
fn assertive_tests_data() -> List(core.AssertiveTestData(Param)) {
  [
    core.AssertiveTestData(
      param: core.is_v_and_tag_equals(_, "keep_this"),
      source: "
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
  core.assertive_test_collection_from_data(
    name,
    assertive_tests_data(),
    constructor,
  )
}
