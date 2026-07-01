import desugarers/delete_outside_subtrees.{
  constructor as delete_outside_subtrees,
}
import gleam/list
import gleam/option
import gleam/string.{inspect as ins}
import infrastructure.{type Desugarer, type DesugaringError, Desugarer} as infra
import nodemaps_2_desugarer_transforms as n2t
import vxml.{type VXML, T, V}

fn should_keep(vxml: VXML, inner: InnerParam) -> Bool {
  case vxml {
    T(..) -> False
    V(_, tag, attrs, _) ->
      list.contains(inner.1, tag)
      || list.any(attrs, fn(attr) {
        list.any(inner.0, fn(kv) { kv.0 == attr.key && kv.1 == attr.val })
      })
  }
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(param)
}

type Param =
  #(List(#(String, String)), List(String))

//                    ↖       ↖
//                    key     value
type InnerParam =
  Param

pub const name = "filter_nodes_by_key_values_while_saving"

//------------------------------------------------53
/// if inner.0 == [], filters nothing
/// 
/// else filters by identifying nodes whose tag is
/// in the 'saved' list inner.1, or else whose attrs
/// match at least one of the given #(key, value) pairs, 
/// counting only perfectly literal matches; keeps only
/// nodes that are descendants of such nodes, or
/// ancestors of such nodes
pub fn constructor(param: Param) -> Desugarer {
  Desugarer(
    name: name,
    stringified_param: option.Some(ins(param)),
    stringified_outside: option.None,
    transform: case param_to_inner_param(param) {
      Error(error) -> fn(_) { Error(error) }
      Ok(inner) ->
        case inner.0 {
          [] -> n2t.identity_transform
          _ -> delete_outside_subtrees(should_keep(_, inner)).transform
        }
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
  infra.assertive_test_collection_from_data(
    name,
    assertive_tests_data(),
    constructor,
  )
}
