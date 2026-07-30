import gleam/option
import desugaring/core.{type Desugarer, Desugarer, type DesugarerTransform, type DesugaringError} as core
import desugaring/nodemaps_2_transform as n2t
import vxml.{type VXML, T}

fn nodemap(
  vxml: VXML,
) -> VXML {
  case vxml {
    T(blame, lines) -> T(blame, lines |> core.lines_map_content(core.normalize_spaces))
    _ -> vxml
  }
}

fn nodemap_factory() -> n2t.OneToOneNoErrorNodemap {
  nodemap
}

fn transform_factory(outside: List(String)) -> DesugarerTransform {
  nodemap_factory()
  |> n2t.one_to_one_no_error_nodemap_2_desugarer_transform_with_forbidden(outside)
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(param)
}

type Param = Nil
type InnerParam = Nil

pub const name = "normalize_spaces__outside"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// turns double or more spaces into single spaces
/// outside of subtrees rooted at tags given by the
/// param argument
pub fn constructor(outside: List(String)) -> Desugarer {
  Desugarer(
    name: name,
    stringified_param: option.None,
    stringified_outside: option.None,
    transform: case param_to_inner_param(Nil) {
      Error(error) -> fn(_) { Error(error) }
      Ok(_) -> transform_factory(outside)
    }
  )
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
fn assertive_tests_data() -> List(core.AssertiveTestDataNoParamWithOutside) {
  []
}

pub fn assertive_tests() {
  core.assertive_test_collection_from_data_no_param_with_outside(name, assertive_tests_data(), constructor)
}
