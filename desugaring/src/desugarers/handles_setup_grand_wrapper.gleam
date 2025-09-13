import gleam/option
import infrastructure.{
  type Desugarer,
  type DesugarerTransform,
  type DesugaringError,
  Desugarer,
  DesugaringError,
} as infra
import nodemaps_2_desugarer_transforms as n2t
import vxml.{type VXML, V}
import blame as bl

fn at_root(vxml: VXML) -> Result(VXML, DesugaringError) {
  let assert V(_, tag, _, _) = vxml
  case tag {
    "GrandWrapper" -> Error(DesugaringError(vxml.blame, "'GrandWrapper' already present!"))
    _ -> {
      Ok(V(
        desugarer_blame(19),
        "GrandWrapper",
        [],
        [vxml],
      ))
    }
  }
}

fn transform_factory(_inner: InnerParam) -> DesugarerTransform {
  at_root
  |> n2t.at_root_2_desugarer_transform
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(param)
}

type Param = Nil
type InnerParam = Nil

pub const name = "handles_setup_grand_wrapper"
fn desugarer_blame(line_no: Int) { bl.Des([], name, line_no) }

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// idempotent desugarer that leaves the VXML
/// unchanged and that never generates an error
pub fn constructor() -> Desugarer {
  Desugarer(
    name: name,
    stringified_param: option.None,
    stringified_outside: option.None,
    transform: case param_to_inner_param(Nil) {
      Error(error) -> fn(_) { Error(error) }
      Ok(inner) -> transform_factory(inner)
    },
  )
}


// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
fn assertive_tests_data() -> List(infra.AssertiveTestDataNoParam) {
  []
}

pub fn assertive_tests() {
  infra.assertive_test_collection_from_data_no_param(name, assertive_tests_data(), constructor)
}
