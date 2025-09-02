import gleam/option
import gleam/string.{inspect as ins}
import infrastructure.{type Desugarer, Desugarer, type DesugarerTransform, type DesugaringError, type TrafficLight, Continue, GoBack} as infra
import nodemaps_2_desugarer_transforms as n2t
import vxml.{type VXML, V, T, TextLine}
import blame as bl
import on

fn nodemap(
  node: VXML,
  inner: InnerParam,
) -> #(VXML, TrafficLight) {
  case node {
    V(_, tag, _, _) if tag == inner.0 -> {
      // return early if we have a child of tag child_tag == inner.1:
      use <- on.nonempty_empty(
        infra.v_children_with_tag(node, inner.1),
        fn(_, _) { #(node, GoBack) },
      )

      // return early if we don't have a attribute_key == inner.2:
      use attribute, _ <- on.empty_nonempty(
        infra.v_attributes_with_key(node, inner.2),
        #(node, GoBack),
      )

      #(
        V(
          ..node,
          children: [
            V(
              desugarer_blame(32),
              inner.1,
              [],
              [T(attribute.blame, [TextLine(attribute.blame, attribute.value)])],
            ),
            ..node.children,
          ]
        ),
        GoBack,
      )
    }
    _ -> #(node, Continue)
  }
}

fn nodemap_factory(inner: InnerParam) -> n2t.EarlyReturnOneToOneNoErrorNodeMap {
  nodemap(_, inner)
}

fn transform_factory(inner: InnerParam, outside: List(String)) -> DesugarerTransform {
  nodemap_factory(inner)
  |> n2t.early_return_one_to_one_no_error_nodemap_2_desugarer_transform_with_forbidden(outside)
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(param)
}

type Param = #(String, String, String)
//             ↖       ↖       ↖        
//             parent  child   attribute
//             tag     tag              
type InnerParam = Param

pub const name = "auto_generate_child_if_missing_from_attribute__outside"
fn desugarer_blame(line_no: Int) {bl.Des([], name, line_no)}

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// Given first 3 arguments
/// ```
/// parent_tag, child_tag, attribute_key
/// ```
/// will, for each node of tag `parent_tag`,
/// generate, if the node has no existing children
/// tag `child_tag`, by using the value of 
/// attribute_key as the contents of the child of 
/// tag child_tag. If no such attribute exists, does
/// nothing to the node of tag parent_tag.
/// 
/// Early-returns from subtree rooted at parent_tag.
/// 
/// Stays outside of trees rooted at tags in last
/// argument given to function.
pub fn constructor(param: Param, outside: List(String)) -> Desugarer {
  Desugarer(
    name: name,
    stringified_param: option.Some(ins(param)),
    stringified_outside: option.Some(ins(outside)),
    transform: case param_to_inner_param(param) {
      Error(error) -> fn(_) { Error(error) }
      Ok(inner) -> transform_factory(inner, outside)
    },
  )
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
fn assertive_tests_data() -> List(infra.AssertiveTestDataWithOutside(Param)) {
  []
}

pub fn assertive_tests() {
  infra.assertive_test_collection_from_data_with_outside(name, assertive_tests_data(), constructor)
}
