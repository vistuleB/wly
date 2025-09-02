import desugarers/delete_outside_subtrees.{constructor as delete_outside_subtrees}
import gleam/list
import gleam/option
import gleam/string.{inspect as ins}
import infrastructure.{type DesugaringError, type Desugarer, Desugarer} as infra
import vxml.{type VXML, V}
import blame as bl
import nodemaps_2_desugarer_transforms as n2t

fn matches_a_selector(vxml: VXML, inner: InnerParam) -> Bool {
  let assert V(blame, _, attrs, _) = vxml
  let v_path = case blame {
    bl.Src(_, v_path, _, _) -> v_path
    _ -> ""
  }
  list.any(inner, fn(selector) {
    let #(path, key, value) = selector
    {
      string.contains(v_path, path)
      && {
        key == ""
        || list.any(attrs, fn(attr) {
          { attr.key == key && attr.value == value }
        })
      }
    }
  })
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(param)
}

type Param = List(#(String,  String,  String))
//                  ↖        ↖        ↖
//                  path     key      value
type InnerParam = Param

pub const name = "filter_nodes_by_attributes"

//------------------------------------------------53
/// filters by identifying nodes whose
/// blame.filename contain the extra.path as a
/// substring and whose attributes match at least
/// one of the given #(key, value) pairs, with a
/// match counting as true if key == ""; keeps only
/// nodes that are descendants of such nodes, or
/// ancestors of such nodes
pub fn constructor(param: Param) -> Desugarer {
  Desugarer(
    name: name,
    stringified_param: option.Some(ins(param)),
    stringified_outside: option.None,
    transform: case param_to_inner_param(param) {
      Error(error) -> fn(_) { Error(error) }
      Ok(inner) -> case inner {
        [] -> n2t.identity_transform
        _ -> delete_outside_subtrees(matches_a_selector(_, inner)).transform
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
