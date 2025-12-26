import gleam/option
import gleam/list
import gleam/string.{inspect as ins}
import infrastructure.{type Desugarer, Desugarer, type DesugarerTransform, type DesugaringError} as infra
import nodemaps_2_desugarer_transforms as n2t
import vxml.{ type VXML, V, type Attr, Attr}

fn map_attr(attr: Attr, state: State, inner: InnerParam) -> Attr {
  case attr.key {
    "handle" -> {
      case attr.val |> string.split_once(" ") {
        Ok(#(_, handle_value)) -> {
          assert string.trim(handle_value) != ""
          attr
        }
        Error(Nil) -> {
          let appended_value = case state {
            True -> inner.2
            False -> inner.3
          }
          Attr(..attr, val: attr.val <> " " <> appended_value)
        }
      }
    }
    _ -> attr
  }
}

fn v_before_nodemap(
  vxml: VXML,
  state: State,
  inner: InnerParam,
) -> #(VXML, State) {
  let assert V(_, tag, attrs, _) = vxml
  let state = state || tag == inner.1
  case tag == inner.0 {
    False -> #(vxml, state)
    True -> {
      #(V(..vxml, attrs: attrs |> list.map(map_attr(_, state, inner))), state)
    }
  }
}

fn nodemap_factory(inner: InnerParam) -> n2t.OneToOneBeforeAndAfterStatefulNoErrorNodemap(State){
  n2t.OneToOneBeforeAndAfterStatefulNoErrorNodemap(
      v_before_transforming_children: fn (vxml, state) { v_before_nodemap(vxml, state, inner) },
      v_after_transforming_children: fn(vxml, original_state, _latest_state) { #(vxml, original_state) },
      t_nodemap: fn(vxml, state) { #(vxml, state) }
    )
}

fn transform_factory(inner: InnerParam) -> DesugarerTransform {
  nodemap_factory(inner)
  |> n2t.one_to_one_before_and_after_stateful_no_error_nodemap_2_desugarer_transform(False)
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  param
  |> Ok
}

type AncestorHasBeenSeen = Bool
type State = AncestorHasBeenSeen

type Param = #(String,    String,    String,      String)
//                ↖       ↖          ↖            ↖
//                tag     ancestor   if_version   else_version
type InnerParam = Param

pub const name = "set_handle_value_if_has_ancestor_else"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// append value to handle attr based on
/// if it has the given ancestor or else append
/// the else version
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
  []
}

pub fn assertive_tests() {
  infra.assertive_test_collection_from_data(name, assertive_tests_data(), constructor)
}
