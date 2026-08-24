import desugaring/core
import desugaring/rearrange_links_engine as engine
import gleam/string.{inspect as ins}

type Param =
  #(String, String)

pub const name = "rearrange_links_4_pre_tokenized_src"

pub fn constructor(param: Param) {
  engine.constructor_for(name, [param], engine.PreTokenizedInput, ins(param))
}

pub fn assertive_tests() {
  core.assertive_test_collection_from_data(name, [], constructor)
}
