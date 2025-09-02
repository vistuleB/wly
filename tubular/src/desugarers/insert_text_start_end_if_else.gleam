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
    V(_, tag, _, _) if tag == inner.0 -> {
      case inner.5(vxml) {
        True ->
          vxml
          |> infra.v_start_insert_text(inner.1)
          |> infra.v_end_insert_text(inner.2)
        False ->
          vxml
          |> infra.v_start_insert_text(inner.3)
          |> infra.v_end_insert_text(inner.4)
      }
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
  #(param.0, param.1.0, param.1.1, param.2.0, param.2.1, param.3)
  |> Ok
}

type Param = #(String, #(String,    String),   #(String,     String),   fn(VXML) -> Bool)
//             ↖         ↖          ↖            ↖           ↖          ↖
//             tag       insert     insert       insert      insert     condition
//                       at start   at end       at start    at end
//                       if case    if case      else case   else case
type InnerParam = #(String, String, String, String, String, fn(VXML) -> Bool)

pub const name = "insert_text_start_end_if_else"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// inserts text at the beginning and end of a
/// specified tag
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
