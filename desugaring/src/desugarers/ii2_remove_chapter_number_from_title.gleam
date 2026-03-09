import gleam/list
import gleam/option
import gleam/regexp
import infrastructure.{
  type Desugarer,
  type DesugarerTransform,
  type DesugaringWarning,
  Desugarer,
  DesugaringWarning,
} as infra
import nodemaps_2_desugarer_transforms as n2t
import vxml.{type VXML, Line, T, V}
import on

fn nodemap(
  vxml: VXML,
) -> #(VXML, List(DesugaringWarning)) {
  case vxml {
    V(blame, t, attrs, children) -> {
      use <- on.false_true(
        infra.v_has_key_val(vxml, "class", "chapterTitle") ||
        infra.v_has_key_val(vxml, "class", "subChapterTitle"),
        on_false: fn() { #(vxml, []) },
      )
      case children {
        [
          T(
            t_blame,
            [Line(l_blame, first_text_node_line), ..rest_contents],
          ),
          ..rest_children,
        ] -> {
          let assert Ok(re) = regexp.from_string("^(\\d+)(\\.(\\d+)?)?\\s")
          use <- on.false_true(
            regexp.check(re, first_text_node_line),
            on_false: fn() { #(vxml, []) },
          )
          let new_line = regexp.replace(re, first_text_node_line, "")
          let contents = T(t_blame, [Line(l_blame, new_line), ..list.drop(rest_contents, 1)])
          let children = [contents, ..list.drop(rest_children, 1)]
          #(V(blame, t, attrs, children), [])
        }
        _ -> {
          let warning = DesugaringWarning(blame, "could not find T(_,_) element")
          #(vxml, [warning])
        }
      }
    }
    _ -> #(vxml, [])
  }
}

fn nodemap_factory(_: InnerParam) -> n2t.OneToOneNoErrorWithWarningsNodemap {
  nodemap
}

fn transform_factory(inner: InnerParam) -> DesugarerTransform {
  n2t.one_to_one_no_error_with_warnings_nodemap_2_desugarer_transform(nodemap_factory(inner))
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, infra.DesugaringError) {
  Ok(param)
}

type Param = Nil
type InnerParam = Nil

pub const name = "ii2_remove_chapter_number_from_title"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// removes chapter numbers from titles in chapter
/// and subchapter title elements
pub fn constructor() -> Desugarer {
  Desugarer(
    name: name,
    stringified_param: option.None,
    stringified_outside: option.None,
    transform: case param_to_inner_param(Nil) {
      Error(error) -> fn(_) { Error(error) }
      Ok(inner) -> transform_factory(inner)
    },
  )
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
fn assertive_tests_data() -> List(infra.AssertiveTestDataNoParam) {
  []
}

pub fn assertive_tests() {
  infra.assertive_test_collection_from_data_no_param(name, assertive_tests_data(), constructor)
}
