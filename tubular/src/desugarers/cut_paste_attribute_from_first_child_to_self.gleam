import gleam/list
import gleam/option.{type Option, Some, None}
import gleam/string.{inspect as ins}
import infrastructure.{type Desugarer, Desugarer, type DesugarerTransform, type DesugaringError} as infra
import nodemaps_2_desugarer_transforms as n2t
import vxml.{type VXML, V, type Attribute}
import on

/// return option of
/// - attribute with key `key`
/// - modified children (with removed attribute)
fn check_first_child(children: List(VXML), key: String)
-> Option(#(Attribute, List(VXML))) {
  use first, rest <- on.empty_nonempty(children, None)
  use _, _, _, _ <- infra.on_t_on_v(first, fn(_, _){None})
  let assert V(_, _, attributes, _) = first
  use attribute <- on.error_ok(
    list.find(attributes, fn(att) {att.key == key}),
    fn(_) { None },
  )
  let first = V(..first, attributes: list.filter(attributes, fn(att) { att.key != key }))
  Some(#(attribute, [first, ..rest]))
}

fn nodemap(
  node: VXML,
  inner: InnerParam,
) -> Result(VXML, DesugaringError) {
  let #(parent_tag, key) = inner
  case node {
    V(_, tag, _, children) if tag == parent_tag -> {
      case check_first_child(children, key) {
        option.None -> Ok(node)
        option.Some(#(att, children)) -> Ok(V(..node, attributes: list.append(node.attributes, [att]), children: children))
      }
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

type Param =
  #(String, String)
//  ↖       ↖
//  parent  attribute
//  tag     key

type InnerParam = Param

pub const name = "cut_paste_attribute_from_first_child_to_self"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// Moves an attribute with key `key` from the first
/// child of a node with tag `parent_tag` to the 
/// node itself.
/// ```
/// #Param:
/// - parent tag
/// - child tag
/// - attribute key
/// ```
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