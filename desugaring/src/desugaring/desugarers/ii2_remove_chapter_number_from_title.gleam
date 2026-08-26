import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringWarning,
  DesugaringWarning,
}
import desugaring/nodemaps_2_transform as n2t
import gleam/list
import gleam/regexp
import on
import vxml.{type VXML, Line, T, V}

fn nodemap(vxml: VXML) -> #(VXML, List(DesugaringWarning)) {
  case vxml {
    V(blame, t, attrs, children) -> {
      use <- on.false_true(
        core.v_has_key_val(vxml, "class", "chapterTitle")
          || core.v_has_key_val(vxml, "class", "subChapterTitle"),
        on_false: fn() { #(vxml, []) },
      )
      case children {
        [
          T(t_blame, [Line(l_blame, first_text_node_line), ..rest_contents]),
          ..rest_children
        ] -> {
          let assert Ok(re) = regexp.from_string("^(\\d+)(\\.(\\d+)?)?\\s")
          use <- on.false_true(
            regexp.check(re, first_text_node_line),
            on_false: fn() { #(vxml, []) },
          )
          let new_line = regexp.replace(re, first_text_node_line, "")
          let contents =
            T(t_blame, [Line(l_blame, new_line), ..list.drop(rest_contents, 1)])
          let children = [contents, ..list.drop(rest_children, 1)]
          #(V(blame, t, attrs, children), [])
        }
        _ -> {
          let warning =
            DesugaringWarning(blame, "could not find T(_,_) element")
          #(vxml, [warning])
        }
      }
    }
    _ -> #(vxml, [])
  }
}

fn inner_param_to_transform(_: InnerParam) -> DesugarerTransform {
  let nodemap: n2t.OneToOneNoErrorWithWarningsNodemap = nodemap
  n2t.one_to_one_no_error_with_warnings_nodemap_2_desugarer_transform(nodemap)
}

type InnerParam =
  Nil

pub const name = "ii2_remove_chapter_number_from_title"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
/// Removes leading chapter numbers from II2 chapter and
/// subchapter title elements, warning on unexpected content.
pub fn constructor() -> Desugarer {
  authoring.no_param_desugarer(
    name: name,
    transform: inner_param_to_transform(Nil),
  )
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊
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
