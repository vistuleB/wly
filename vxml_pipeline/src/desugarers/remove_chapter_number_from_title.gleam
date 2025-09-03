import gleam/list
import gleam/option
import gleam/regexp
import infrastructure.{ type Desugarer, Desugarer, type DesugarerTransform, type DesugaringError} as infra
import nodemaps_2_desugarer_transforms as n2t
import vxml.{type VXML, TextLine, T, V}
import on

fn nodemap(
  vxml: VXML,
) -> Result(VXML, DesugaringError) {
  case vxml {
    V(blame, t, atts, children) -> {
      // remove carousel buttons
      use <- on.false_true(
        infra.v_has_key_value(vxml, "class", "chapterTitle") ||
        infra.v_has_key_value(vxml, "class", "subChapterTitle"),
        on_false: Ok(vxml),
      )

      let assert [
        T(
          t_blame,
          [TextLine(l_blame, first_text_node_line), ..rest_contents],
        ),
        ..rest_children
      ] = children
      let assert Ok(re) = regexp.from_string("^(\\d+)(\\.(\\d+)?)?\\s")
      regexp.check(re, first_text_node_line)

      use <- on.false_true(
        regexp.check(re, first_text_node_line),
        on_false: Ok(vxml),
      )

      let new_line = regexp.replace(re, first_text_node_line, "")
      let contents = T(t_blame, [TextLine(l_blame, new_line), ..list.drop(rest_contents, 1)])
      let children = [contents, ..list.drop(rest_children, 1)]

      Ok(V(blame, t, atts, children))
    }
    _ -> Ok(vxml)
  }
}

fn nodemap_factory(_: InnerParam) -> n2t.OneToOneNodeMap {
  nodemap
}

fn transform_factory(inner: InnerParam) -> DesugarerTransform {
  n2t.one_to_one_nodemap_2_desugarer_transform(nodemap_factory(inner))
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(param)
}

type Param = Nil
type InnerParam = Nil

pub const name = "remove_chapter_number_from_title"

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
