import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError, DesugaringError,
}
import desugaring/nodemaps_2_transform as n2t
import gleam/list
import gleam/result
import gleam/string
import vxml.{type Attr, type VXML, Attr, V}

pub const name = "set_handle_value_if_has_ancestor_else"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Appends one of two handle values according to whether
/// each target has a configured ancestor.
pub fn constructor(param: Param) -> Desugarer {
  authoring.desugarer(
    name: name,
    param: param,
    prepare: param_to_inner_param,
    transform: inner_param_to_transform,
  )
}

type Param =
  #(
    // Target tag.
    String,
    // Required ancestor tag.
    String,
    // Value used inside the ancestor.
    String,
    // Value used outside the ancestor.
    String,
  )

type InnerParam =
  Param

type AncestorHasBeenSeen =
  Bool

type State =
  AncestorHasBeenSeen

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  param
  |> Ok
}

fn inner_param_to_transform(inner: InnerParam) -> DesugarerTransform {
  nodemap_factory(inner)
  |> n2t.one_to_one_enter_exit_stateful_nodemap_2_desugarer_transform(False)
}

fn nodemap_factory(
  inner: InnerParam,
) -> n2t.OneToOneEnterExitStatefulNodemap(State) {
  n2t.OneToOneEnterExitStatefulNodemap(
    on_enter: fn(vxml, state) { v_before_nodemap(vxml, state, inner) },
    on_exit: fn(vxml, original_state, _latest_state) {
      Ok(#(vxml, original_state))
    },
    on_text: fn(vxml, state) { Ok(#(vxml, state)) },
  )
}

fn v_before_nodemap(
  vxml: VXML,
  state: State,
  inner: InnerParam,
) -> Result(#(VXML, State), DesugaringError) {
  let assert V(_, tag, attrs, _) = vxml
  let state = state || tag == inner.1
  case tag == inner.0 {
    False -> Ok(#(vxml, state))
    True -> {
      use attrs <- result.try(list.try_map(attrs, map_attr(_, state, inner)))
      Ok(#(V(..vxml, attrs: attrs), state))
    }
  }
}

fn map_attr(
  attr: Attr,
  state: State,
  inner: InnerParam,
) -> Result(Attr, DesugaringError) {
  case attr.key {
    "handle" ->
      case attr.val |> string.split_once(" ") {
        Ok(#(_, handle_value)) ->
          case string.trim(handle_value) == "" {
            True -> Error(malformed_handle_error(attr))
            False -> Ok(attr)
          }
        Error(Nil) -> {
          let appended_value = case state {
            True -> inner.2
            False -> inner.3
          }
          Ok(Attr(..attr, val: attr.val <> " " <> appended_value))
        }
      }
    _ -> Ok(attr)
  }
}

fn malformed_handle_error(attr: Attr) -> DesugaringError {
  DesugaringError(attr.blame, "handle contains a space but no value follows it")
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊

fn assertive_tests_data() -> List(core.AssertiveTestData(Param)) {
  []
}

pub fn assertive_tests() {
  core.assertive_test_collection_from_data(
    name,
    assertive_tests_data(),
    constructor,
  )
}
