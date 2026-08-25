import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError, Desugarer,
}
import gleam/option
import gleam/string
import vxml/blame.{type Blame, Des}

pub fn desugarer(
  name name: String,
  param param: a,
  prepare prepare: fn(a) -> Result(b, DesugaringError),
  transform transform: fn(b) -> DesugarerTransform,
) -> Desugarer {
  desugarer_with_stringified_param(
    name: name,
    param: param,
    stringified_param: string.inspect(param),
    prepare: prepare,
    transform: transform,
  )
}

pub fn desugarer_with_stringified_param(
  name name: String,
  param param: a,
  stringified_param stringified_param: String,
  prepare prepare: fn(a) -> Result(b, DesugaringError),
  transform transform: fn(b) -> DesugarerTransform,
) -> Desugarer {
  Desugarer(
    name: name,
    stringified_param: option.Some(stringified_param),
    stringified_outside: option.None,
    transform: case prepare(param) {
      Ok(prepared) -> transform(prepared)
      Error(error) -> fn(_) { Error(error) }
    },
  )
}

pub fn infallible_desugarer(
  name name: String,
  param param: a,
  transform transform: fn(a) -> DesugarerTransform,
) -> Desugarer {
  Desugarer(
    name: name,
    stringified_param: option.Some(string.inspect(param)),
    stringified_outside: option.None,
    transform: transform(param),
  )
}

pub fn no_param_desugarer(
  name name: String,
  transform transform: DesugarerTransform,
) -> Desugarer {
  Desugarer(
    name: name,
    stringified_param: option.None,
    stringified_outside: option.None,
    transform: transform,
  )
}

pub fn blame(name: String, line_no: Int) -> Blame {
  Des([], name, line_no)
}
