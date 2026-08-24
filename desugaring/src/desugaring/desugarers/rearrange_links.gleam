import desugaring/rearrange_links_engine as engine
import gleam/string.{inspect as ins}

type Param =
  #(String, String)

pub const name = "rearrange_links"

pub fn constructor(param: Param) {
  engine.constructor_for(name, [param], engine.RawInput, ins(param))
}

pub fn assertive_tests() {
  engine.single_assertive_tests(name, constructor)
}
