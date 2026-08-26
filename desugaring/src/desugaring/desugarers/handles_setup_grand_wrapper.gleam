import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError, DesugaringError,
}
import desugaring/nodemaps_2_transform as n2t
import vxml.{type VXML, V}
import vxml/blame as bl

fn at_root(vxml: VXML) -> Result(VXML, DesugaringError) {
  let assert V(_, tag, _, _) = vxml
  case tag {
    "GrandWrapper" ->
      Error(DesugaringError(vxml.blame, "'GrandWrapper' already present!"))
    _ -> {
      Ok(V(desugarer_blame(15), "GrandWrapper", [], [vxml]))
    }
  }
}

fn inner_param_to_transform(_inner: InnerParam) -> DesugarerTransform {
  at_root
  |> n2t.node_to_node_2_desugarer_transform_without_walking
}

type InnerParam =
  Nil

pub const name = "handles_setup_grand_wrapper"

fn desugarer_blame(line_no: Int) {
  bl.Des([], name, line_no)
}

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
/// Ensures the root is a `GrandWrapper`, rejecting a
/// differently named root that already has wrapper metadata.
pub fn constructor() -> Desugarer {
  authoring.no_param_desugarer(
    name: name,
    transform: inner_param_to_transform(Nil),
  )
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
fn assertive_tests_data() -> List(core.AssertiveTestDataNoParam) {
  []
}

pub fn assertive_tests() {
  core.assertive_test_collection_from_data_no_param(
    name,
    assertive_tests_data(),
    constructor,
  )
}
