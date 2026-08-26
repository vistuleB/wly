import desugaring/core.{type Desugarer}
import desugaring/rearrange_links_engine as engine
import gleam/string.{inspect as ins}

pub const name = "rearrange_links_4_pre_tokenized_src__batch"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Rearranges multiple link prefixes whose source
/// attributes are already tokenized.
pub fn constructor(param: engine.Param) -> Desugarer {
  engine.constructor_for(name, param, engine.PreTokenizedInput, ins(param))
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊

pub fn assertive_tests() {
  core.assertive_test_collection_from_data(name, [], constructor)
}
