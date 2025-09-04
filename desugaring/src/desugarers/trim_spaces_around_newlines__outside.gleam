import gleam/option
import infrastructure.{type Desugarer, Desugarer, type DesugarerTransform, type DesugaringError} as infra
import nodemaps_2_desugarer_transforms as n2t
import vxml.{type VXML, T}

fn nodemap(
  vxml: VXML,
) -> VXML {
  case vxml {
    T(_, _) ->
      vxml
      |> infra.trim_ending_spaces_except_last_line
      |> infra.trim_starting_spaces_except_first_line
    _ -> vxml
  }
}

fn nodemap_factory() -> n2t.OneToOneNoErrorNodeMap {
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

pub const name = "trim_spaces_around_newlines__outside"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// trims spaces around newlines in text nodes
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
fn assertive_tests_data() -> List(infra.AssertiveTestDataNoParamWithOutside) {
  []
}

pub fn assertive_tests() {
  infra.assertive_test_collection_from_data_no_param_with_outside(name, assertive_tests_data(), constructor)
}
