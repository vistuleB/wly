import desugarers/delete_outside_subtrees_v2.{constructor as delete_outside_subtrees_v2}
import gleam/list
import gleam/option
import gleam/string.{inspect as ins}
import infrastructure.{type DesugaringError, type Desugarer, Desugarer} as infra
import vxml.{type VXML, V, T}
import nodemaps_2_desugarer_transforms as n2t
import blame as bl

fn matches_a_path_key_value(vxml: VXML, inner: InnerParam) -> Bool {
  case vxml {
    T(..) -> False
    V(_, _, [], _) -> False
    V(b, _, attrs, _) -> list.any(inner, fn(pkv) {
      !bl.path_contains(b, pkv.0) ||
      list.any(attrs, fn(attr) { pkv.1 == attr.key && pkv.2 == attr.val })
    })
  }
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(param)
}

type Param = List(#(String, String,  String))
//                  ↖        ↖        ↖
//                  path     key      value
type InnerParam = Param

pub const name = "filter_nodes_by_path_key_values"

//------------------------------------------------53
/// keeps nodes that match one of the inner tuples
/// in the following maybe counterintuitive sense; a
/// node matches #(path, key, val) if either
///
///    - 'path' is not contained in the node's
///      blame.path (so that selector is "aimed"
///      only at nodes with a certain path/blame)
///    - the node is a V(..) and key=val is one of the 
///      node's attributes
/// 
/// in other words, if you *do* match the path, then
/// and only then do you need to worry about matching
/// one of the key-val pairs
pub fn constructor(param: Param) -> Desugarer {
  Desugarer(
    name: name,
    stringified_param: option.Some(ins(param)),
    stringified_outside: option.None,
    transform: case param_to_inner_param(param) {
      Error(error) -> fn(_) { Error(error) }
      Ok(inner) -> case inner {
        [] -> n2t.identity_transform
        _ -> delete_outside_subtrees_v2(matches_a_path_key_value(_, inner)).transform
      }
    }
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
