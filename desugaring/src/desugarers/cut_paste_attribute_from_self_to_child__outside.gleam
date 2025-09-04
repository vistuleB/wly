import gleam/list
import gleam/option
import gleam/string.{inspect as ins}
import infrastructure.{type Desugarer, Desugarer, type DesugarerTransform, type DesugaringError, type TrafficLight, Continue, GoBack} as infra
import nodemaps_2_desugarer_transforms as n2t
import vxml.{type VXML, V, type Attribute}

fn update_child(
  child: VXML,
  child_tag: String,
  attribute: Attribute,
) -> VXML {
  case child {
    V(_, tag, _, _) if tag == child_tag ->
      V(..child, attributes: list.append(child.attributes, [attribute]))
    _ -> child
  }
}

fn nodemap(
  node: VXML,
  inner: InnerParam,
) -> #(VXML, TrafficLight) {
  case node {
    V(_, tag, _, _) if tag == inner.0 -> {
      case infra.v_first_attribute_with_key(node, inner.2) {
        option.None -> #(node, GoBack)
        option.Some(attribute) -> #(
          V(
            ..node,
            attributes: node.attributes |> list.filter(fn(x) { x.key != inner.2 }),
            children: node.children |> list.map(update_child(_, inner.1, attribute)),
          ),
          GoBack
        )
      }
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
type InnerParam = Param

pub const name = "cut_paste_attribute_from_self_to_child__outside"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// For all nodes with a given 'parent_tag',
/// removes all attributes of a given key. If the 
/// list of removed attributes is nonempty, pastes
/// the first element of the list to all children
/// of the `parent_tag` node that have a given 
/// `child_tag` tag.
/// 
/// Returns early after encountering a node of tag
/// 'parent_tag'.
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
