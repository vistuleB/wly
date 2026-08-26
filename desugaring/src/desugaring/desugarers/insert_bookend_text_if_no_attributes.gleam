import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
}
import desugaring/nodemaps_2_transform as n2t
import gleam/list
import gleam/pair
import vxml.{type VXML, V}

fn nodemap(vxml: VXML, inner: InnerParam) -> Result(VXML, DesugaringError) {
  case vxml {
    V(_, tag, [], _) -> {
      case list.find(inner, fn(pair) { pair |> pair.first == tag }) {
        Error(Nil) -> Ok(vxml)
        Ok(#(_, #(start_text, end_text))) -> {
          vxml
          |> core.v_start_insert_text(start_text)
          |> core.v_end_insert_text(end_text)
          |> Ok
        }
      }
    }
    _ -> Ok(vxml)
  }
}

fn inner_param_to_transform(inner: InnerParam) -> DesugarerTransform {
  let nodemap: n2t.OneToOneNodemap = nodemap(_, inner)
  n2t.one_to_one_nodemap_2_desugarer_transform(nodemap)
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  param
  |> core.triples_to_pairs
  |> Ok
}

type Param =
  List(
    #(
      // Target element name.
      String,
      // Text inserted at the start.
      String,
      // Text inserted at the end.
      String,
    ),
  )

type InnerParam =
  List(#(String, #(String, String)))

pub const name = "insert_bookend_text_if_no_attributes"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
/// Inserts configured text at both ends of matching
/// elements that have no attributes.
pub fn constructor(param: Param) -> Desugarer {
  authoring.desugarer(
    name: name,
    param: param,
    prepare: param_to_inner_param,
    transform: inner_param_to_transform,
  )
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
