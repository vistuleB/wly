import gleam/option
import gleam/string.{inspect as ins}
import infrastructure.{type Desugarer, Desugarer, type DesugarerTransform, type DesugaringError} as infra
import nodemaps_2_desugarer_transforms as n2t
import vxml.{type VXML, V}

fn nodemap(
  vxml: VXML,
  inner: InnerParam,
) -> VXML {
  case vxml {
    V(_, tag, [one], _) if tag == inner.0 && one.key == inner.1 && one.val == inner.2 -> {
      vxml
      |> infra.v_start_insert_text(inner.3)
      |> infra.v_end_insert_text(inner.4)
    }
    _ -> vxml
  }
}

fn nodemap_factory(inner: InnerParam) -> n2t.OneToOneNoErrorNodeMap {
  nodemap(_, inner)
}

fn transform_factory(inner: InnerParam) -> DesugarerTransform {
  n2t.one_to_one_no_error_nodemap_2_desugarer_transform(nodemap_factory(inner))
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  #(param.0, param.1, param.2, param.3.0, param.3.1)
  |> Ok
}

type Param = #(String,  String,  String,  #(String,    String))
//             ↖        ↖        ↖          ↖          ↖
//             tag      key      value      insert     insert
//                                          at start   at end
type InnerParam = #(String, String, String, String, String)

pub const name = "insert_text_start_end_if_unique_attr"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// inserts spectified 'begin' and 'end' text to
/// nodes of a given tag whose attrs consist
/// of a list of length 1 that exactly matches a
/// given key/value pair
pub fn constructor(param: Param) -> Desugarer {
  let assert Ok(inner) = param_to_inner_param(param)
  Desugarer(
    name: name,
    stringified_param: option.Some(ins(inner)),
    stringified_outside: option.None,
    transform: transform_factory(inner),
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
