import desugarers/append_class_to_child_if.{constructor as append_class_to_child_if}
import gleam/option
import gleam/string.{inspect as ins}
import infrastructure.{type DesugaringError, type Desugarer, Desugarer} as infra

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(param)
}

type Param = #(String,  String,   List(String))
//             ↖        ↖         ↖
//             parent   class to  if is not one
//                      append    of these tags
type InnerParam = Param

pub const name = "append_class_to_child_if_is_not_one_of"

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
      Ok(inner) -> append_class_to_child_if(#(inner.0, inner.1, infra.is_v_and_tag_is_not_one_of(_, inner.2))).transform
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
