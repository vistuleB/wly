import gleam/list
import gleam/option
import gleam/string.{inspect as ins}
import infrastructure.{type Desugarer, Desugarer, type DesugarerTransform, type DesugaringError} as infra
import nodemaps_2_desugarer_transforms as n2t
import vxml.{type VXML}

fn v_before_transforming_children(vxml: VXML, state: State, inner: InnerParam) -> #(VXML, State) {
  let state = case state.0 || !list.contains(inner.0, infra.v_get_tag(vxml)) {
    True -> state
    False -> #(True, inner.1.0, inner.1.1)
  }
  #(vxml, state)
}

fn v_after_transforming_children(vxml: VXML, original_state: State, _latest_state: State) -> #(VXML, State) {
  #(vxml, original_state)
}

fn t_transform(vxml: VXML, state: State) -> #(VXML, State) {
  #(infra.t_find_replace(vxml, state.1, state.2), state)
}

fn nodemap_factory(inner: InnerParam) -> n2t.OneToOneNoErrorBeforeAndAfterStatefulNodemap(State) {
  n2t.OneToOneNoErrorBeforeAndAfterStatefulNodemap(
    v_before_transforming_children: fn(vxml, state) { v_before_transforming_children(vxml, state, inner) },
    v_after_transforming_children: v_after_transforming_children,
    t_nodemap: t_transform,
  )
}

fn transform_factory(inner: InnerParam) -> DesugarerTransform {
  let state = #(False, inner.2.0, inner.2.1)
  nodemap_factory(inner)
  |> n2t.one_to_one_no_error_before_and_after_stateful_nodemap_2_desugarer_transform(state)
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(param)
}

type State = #(Bool,         String,            String)
//             ↖             ↖                  ↖
//             have we        current 'from'    current 'to'
//             seen ancestor
//             yet or no

type Param = #(List(String), #(String, String), #(String, String))
//             ↖             ↖                  ↖
//             ancestors     if version         else version
type InnerParam = Param

pub const name = "find_replace_if_has_ancestor_else"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// replaces literal occurrences of a string with another 
/// based on whether the text node has any of the specified ancestors
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
      param: #(["special"], #("``", "“"), #("``", "`")),
      source: "
                <> root
                  <> special
                    <>
                      'First line ``'
                      'Second line ``'
                  <> ordinary
                    <>
                      'Outside special ``'
                ",
      expected: "
                <> root
                  <> special
                    <>
                      'First line “'
                      'Second line “'
                  <> ordinary
                    <>
                      'Outside special `'
                ",
    ),
  ]
}

pub fn assertive_tests() {
  infra.assertive_test_collection_from_data(name, assertive_tests_data(), constructor)
}