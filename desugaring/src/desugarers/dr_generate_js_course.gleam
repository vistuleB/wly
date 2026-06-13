import gleam/int
import gleam/list
import gleam/option
import gleam/string.{inspect as ins}
import infrastructure.{
  type Desugarer,
  type DesugarerTransform,
  type DesugaringError,
  type TrafficLight,
  Continue,
  Desugarer,
  DesugaringError,
  GoBack,
} as infra
import nodemaps_2_desugarer_transforms as n2t
import blame as bl
import on
import simplifile
import vxml.{type VXML, V}

// 🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸
// 🌸 chapter map collection 🌸
// 🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸

fn chapter_has_content(vxml: VXML) -> Bool {
  let assert V(_, "Chapter", _, children) = vxml
  case children {
    [] -> False
    [V(_, "ChapterTitle", _, _)] -> False
    [V(_, "Section", _, _), ..] -> False
    [V(_, "ChapterTitle", _, _), V(_, "Section", _, _), ..] -> False
    _ -> True
  }
}

fn chapter_has_section(vxml: VXML) -> Bool {
  let assert V(_, "Chapter", _, children) = vxml
  list.any(children, fn(child) {
    case child {
      V(_, "Section", _, _) -> True
      _ -> False
    }
  })
}

// state: chapter values accumulated in reverse order (0 = chapter has content,
//        1 = chapter has no content but has a Section)
type State =
  List(Int)

fn chapter_collector(
  vxml: VXML,
  state: State,
) -> Result(#(State, TrafficLight), DesugaringError) {
  case vxml {
    V(_, "Document", _, _) -> Ok(#(state, Continue))
    V(chapter_blame, "Chapter", _, _) -> {
      case chapter_has_content(vxml) {
        True -> Ok(#([0, ..state], GoBack))
        False ->
          case chapter_has_section(vxml) {
            True -> Ok(#([1, ..state], GoBack))
            False ->
              Error(DesugaringError(
                chapter_blame,
                "The chapter has either no content or section",
              ))
          }
      }
    }
    _ -> Ok(#(state, GoBack))
  }
}

// 🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸
// 🌸 JS content builder 🌸
// 🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸

fn build_course_js(chapter_values: List(Int)) -> String {
  let entries =
    list.index_map(chapter_values, fn(value, i) {
      "  " <> int.to_string(i + 1) <> ": " <> int.to_string(value) <> ","
    })
    |> string.join("\n")
  "const chapterMap = {\n" <> entries <> "\n};\n"
}

// 🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸
// 🌸 transform 🌸
// 🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸

fn at_root(
  root: VXML,
  inner: InnerParam,
) -> Result(Nil, DesugaringError) {
  use chapter_values_reversed <- on.ok(
    n2t.early_return_identity_stateful_walk(root, [], chapter_collector),
  )
  let content = build_course_js(list.reverse(chapter_values_reversed))
  let path = inner <> "/course.js"
  use error <- on.error(simplifile.write(path, content))
  Error(DesugaringError(
    desugarer_blame(103),
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
  Ok(param |> infra.drop_suffix("/") <> "/public")
}

type Param = String
type InnerParam = String

pub const name = "dr_generate_js_course"
fn desugarer_blame(line_no: Int) { bl.Des([], name, line_no) }

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// takes a course name (e.g. "235A") and writes course.js to
/// <course_name>/public/course.js containing a chapterMap where
/// each key is a chapter number (1-based) and the value is:
///   0  – the chapter has content (url points to the chapter itself)
///   1  – the chapter has no content but has a Section child
///         (url points to the first section)
/// throws DesugaringError if a chapter has neither content nor a Section.
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
