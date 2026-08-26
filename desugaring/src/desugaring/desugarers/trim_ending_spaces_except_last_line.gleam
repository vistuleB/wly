import desugaring/authoring
import desugaring/core.{type Desugarer, type DesugarerTransform}
import desugaring/nodemaps_2_transform as n2t
import vxml.{type VXML, T}

pub const name = "trim_ending_spaces_except_last_line"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Trims ending spaces from every text line except the last.
pub fn constructor() -> Desugarer {
  authoring.no_param_desugarer(
    name: name,
    transform: inner_param_to_transform(),
  )
}

fn nodemap(vxml: VXML) -> VXML {
  case vxml {
    T(_, _) ->
      vxml
      |> core.trim_ending_spaces_except_last_line
    _ -> vxml
  }
}

fn nodemap_factory() -> n2t.OneToOneNoErrorNodemap {
  nodemap
}

fn inner_param_to_transform() -> DesugarerTransform {
  nodemap_factory()
  |> n2t.one_to_one_no_error_nodemap_2_desugarer_transform()
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊🌊
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
