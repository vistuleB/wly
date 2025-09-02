import gleam/option
import gleam/string.{inspect as ins}
import infrastructure.{type Desugarer, Desugarer, type DesugarerTransform, type DesugaringError} as infra
import nodemaps_2_desugarer_transforms as n2t
import vxml.{type VXML, V}
import on

fn nodemap(
  node: VXML,
  inner: InnerParam,
) -> Result(VXML, DesugaringError) {
  let #(parent_tag, child_tag, descendant_tag) = inner
  case node {
    V(_, tag, _, _) if tag == parent_tag -> {
      // return early if we have a child of tag child_tag:
      use <- on.nonempty_empty(
        infra.v_children_with_tag(node, child_tag),
        fn(_, _) { Ok(node) },
      )

      // return early if we don't have a descendant of tag descendant_tag:
      use descendant, _ <- on.empty_nonempty(
        infra.descendants_with_tag(node, descendant_tag),
        Ok(node),
      )

      let assert V(_, _, _, _) = descendant

      Ok(V(
        ..node,
        children: [
          V(
            ..descendant,
            tag: child_tag,
          ),
          ..node.children
        ]
      ))
    }

    _ -> Ok(node)
  }
}

fn nodemap_factory(inner: InnerParam) -> n2t.OneToOneNodeMap {
  nodemap(_, inner)
}

fn transform_factory(inner: InnerParam) -> DesugarerTransform {
  n2t.one_to_one_nodemap_2_desugarer_transform(nodemap_factory(inner))
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(param)
}

type Param = #(String, String, String)
//             ↖       ↖       ↖
//             parent  child   descendant
//             tag     tag     tag

type InnerParam = Param

pub const name = "auto_generate_child_if_missing_from_first_descendant_of_type"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// Given arguments
/// ```
/// parent_tag, child_tag, descendant_tag
/// ```
/// will, for each node of tag `parent_tag`,
/// generate, if the node has no existing
/// children tag `child_tag`, a node of type
/// `child_tag` by copy-pasting the contents
/// and attributes of the first descendant
/// of `parent_tag` that has tag `descendant_tag`.
/// If no such descendant exists, does nothing
/// to the node of tag `parent_tag`.
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
