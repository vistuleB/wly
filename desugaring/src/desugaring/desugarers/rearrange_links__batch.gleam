import desugaring/rearrange_links_engine as engine
import gleam/string.{inspect as ins}

pub const name = "rearrange_links__batch"

pub fn constructor(param: engine.Param) {
  engine.constructor_for(name, param, engine.RawInput, ins(param))
}

pub fn assertive_tests() {
  engine.assertive_tests()
}
