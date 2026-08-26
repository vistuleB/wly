import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
}
import desugaring/nodemaps_2_transform as n2t
import vxml.{type VXML, V}

fn nodemap(vxml: VXML, inner: InnerParam) -> VXML {
  case vxml {
    V(_, tag, _, _) if tag == inner.0 -> {
      case inner.5(vxml) {
        True ->
          vxml
          |> core.v_start_insert_text(inner.1)
          |> core.v_end_insert_text(inner.2)
        False ->
          vxml
          |> core.v_start_insert_text(inner.3)
          |> core.v_end_insert_text(inner.4)
      }
    }
    _ -> vxml
  }
}

fn inner_param_to_transform(inner: InnerParam) -> DesugarerTransform {
  let nodemap: n2t.OneToOneNoErrorNodemap = nodemap(_, inner)
  n2t.one_to_one_no_error_nodemap_2_desugarer_transform(nodemap)
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  #(param.0, param.1.0, param.1.1, param.2.0, param.2.1, param.3)
  |> Ok
}

type Param =
  #(
    // Target element name.
    String,
    // Text inserted at the start and end when true.
    #(String, String),
    // Text inserted at the start and end when false.
    #(String, String),
    // Condition selecting the text pair.
    fn(VXML) -> Bool,
  )

type InnerParam =
  #(String, String, String, String, String, fn(VXML) -> Bool)

pub const name = "insert_text_start_end_if_else"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
/// Inserts one of two configured text pairs around matching
/// elements according to a predicate.
pub fn constructor(param: Param) -> Desugarer {
  authoring.desugarer_with_stringified_param(
    name: name,
    param: param,
    stringified_param: "<function>",
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
