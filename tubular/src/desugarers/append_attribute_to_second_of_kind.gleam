import gleam/list
import gleam/option
import gleam/string.{inspect as ins}
import infrastructure.{type Desugarer, Desugarer, type DesugarerTransform, type DesugaringError} as infra
import nodemaps_2_desugarer_transforms as n2t
import vxml.{type VXML, Attribute, V}
import blame as bl

fn nodemap(
  node: VXML,
  previous_unmapped_siblings: List(VXML),
  inner: InnerParam,
) -> Result(VXML, DesugaringError) {
  case node, previous_unmapped_siblings {
    V(_, tag, attrs, _), [V(_, prev_tag, _, _), ..] if tag == inner.0 && prev_tag == inner.0 -> {
      let new_attr = Attribute(desugarer_blame(16), inner.1, inner.2)
      Ok(V(..node, attributes: list.append(attrs, [new_attr])))
    }
    _, _ -> Ok(node)
  }
}

fn nodemap_factory(inner: InnerParam) -> n2t.FancyOneToOneNodeMap {
  fn(node, _, prev_siblings, _, _) {
    nodemap(node, prev_siblings, inner)
  }
}

fn transform_factory(inner: InnerParam) -> DesugarerTransform {
  n2t.fancy_one_to_one_nodemap_2_desugarer_transform(nodemap_factory(inner))
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(param)
}

type Param = #(String, String, String)
//             ↖       ↖       ↖
//             tag     key     value

type InnerParam = Param

pub const name = "append_attribute_to_second_of_kind"
fn desugarer_blame(line_no: Int) {bl.Des([], name, line_no)}

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// Adds the specified attribute-value pair to nodes
/// with the given tag name when the previous
/// sibling is also a node with the same tag name
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
  [
    infra.AssertiveTestData(
      param: #("A", "key1", "val1"),
      source:   "
                <> root
                  <> A
                  <> A
                  <> B
                  <> A
                ",
      expected: "
                <> root
                  <> A
                  <> A
                    key1=val1
                  <> B
                  <> A
                "
    ),
    infra.AssertiveTestData(
      param: #("A", "key1", "val1"),
      source:   "
                <> root
                  <> B
                  <> B
                  <> A
                  <> A
                  <> A
                ",
      expected: "
                <> root
                  <> B
                  <> B
                  <> A
                  <> A
                    key1=val1
                  <> A
                    key1=val1
                "
    ),
  ]
}

pub fn assertive_tests() {
  infra.assertive_test_collection_from_data(name, assertive_tests_data(), constructor)
}
