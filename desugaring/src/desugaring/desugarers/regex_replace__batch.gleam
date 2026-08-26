import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
}
import desugaring/nodemaps_2_transform as n2t
import desugaring/regex_replace_engine as engine

pub const name = "regex_replace__batch"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Applies multiple regular-expression replacements throughout
/// all text nodes.
pub fn constructor(param: Param) -> Desugarer {
  authoring.desugarer(
    name: name,
    param: param,
    prepare: param_to_inner_param,
    transform: inner_param_to_transform,
  )
}

type Param =
  List(
    #(
      // Regular-expression pattern.
      String,
      // Replacement text.
      String,
    ),
  )

type InnerParam =
  List(engine.Rule)

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  engine.prepare_batch(param)
}

fn inner_param_to_transform(inner: InnerParam) -> DesugarerTransform {
  let nodemap: n2t.OneToOneNoErrorNodemap = engine.nodemap_batch(_, inner)
  n2t.one_to_one_no_error_nodemap_2_desugarer_transform(nodemap)
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊

fn assertive_tests_data() -> List(core.AssertiveTestData(Param)) {
  [
    core.AssertiveTestData(
      param: [#("[0-9]+", "#"), #("_+", "-")],
      source: "
                <> root
                  <>
                    'item_12'
                ",
      expected: "
                <> root
                  <>
                    'item-#'
                ",
    ),
  ]
}

pub fn assertive_tests() {
  core.assertive_test_collection_from_data(
    name,
    assertive_tests_data(),
    constructor,
  )
}
