import gleam/option
import gleam/string.{inspect as ins}
import infrastructure.{
  type Desugarer,
  type DesugarerTransform,
  type DesugaringError,
  Desugarer,
  DesugaringError,
} as infra
import nodemaps_2_desugarer_transforms as n2t
import blame as bl
import on
import simplifile
import vxml.{type VXML}

const course_js_content =
  "const chapterMap = {
  1: 1,
  2: 1,
  3: 1,
  4: 1,
  5: 0,
  6: 0,
  7: 1,
  8: 1,
  9: 1,
  10: 1,
  11: 0,
  12: 1,
  13: 1,
  14: 1,
  15: 1,
  16: 1,
};
"

fn at_root(
  _root: VXML,
  inner: InnerParam,
) -> Result(Nil, DesugaringError) {
  let path = inner <> "/course.js"
  use error <- on.error(simplifile.write(path, course_js_content))
  Error(DesugaringError(
    desugarer_blame(42),
    "failed to write course.js to '"
      <> path
      <> "': "
      <> simplifile.describe_error(error),
  ))
}

fn transform_factory(inner: InnerParam) -> DesugarerTransform {
  at_root(_, inner)
  |> n2t.at_root_no_changes_2_desugarer_transform()
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(param |> infra.drop_suffix("/"))
}

type Param = String
type InnerParam = String

pub const name = "dr_generate_js_course_235A"
fn desugarer_blame(line_no: Int) { bl.Des([], name, line_no) }

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// writes course.js to the given path with a chapterMap
/// for course 235A
pub fn constructor(param: Param) -> Desugarer {
  Desugarer(
    name: name,
    stringified_param: option.Some(ins(param)),
    stringified_outside: option.None,
    transform: case param_to_inner_param(param) {
      Error(error) -> fn(_) { Error(error) }
      Ok(inner) -> transform_factory(inner)
    },
  )
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
fn assertive_tests_data() -> List(infra.AssertiveTestData(Param)) {
  []
}

pub fn assertive_tests() {
  infra.assertive_test_collection_from_data(name, assertive_tests_data(), constructor)
}
