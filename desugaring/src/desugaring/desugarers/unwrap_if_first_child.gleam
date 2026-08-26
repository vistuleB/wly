import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
}
import desugaring/nodemaps_2_transform as n2t
import gleam/list
import vxml.{type VXML, V}

pub const name = "unwrap_if_first_child"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Repeatedly unwraps matching first children of parent elements.
pub fn constructor(param: Param) -> Desugarer {
  authoring.desugarer(
    name: name,
    param: param,
    prepare: param_to_inner_param,
    transform: inner_param_to_transform,
  )
}

fn map_children(children: List(VXML), inner: InnerParam) -> List(VXML) {
  case children {
    [V(_, tag, _, grandchildren), ..more] if tag == inner ->
      case grandchildren {
        [] -> map_children(more, inner)
        _ -> map_children(list.append(grandchildren, more), inner)
      }
    _ -> children
  }
}

fn nodemap(node: VXML, inner: InnerParam) -> VXML {
  case node {
    V(_, _, _, children) -> V(..node, children: map_children(children, inner))
    _ -> node
  }
}

fn nodemap_factory(inner: InnerParam) -> n2t.OneToOneNoErrorNodemap {
  nodemap(_, inner)
}

fn inner_param_to_transform(inner: InnerParam) -> DesugarerTransform {
  nodemap_factory(inner)
  |> n2t.one_to_one_no_error_nodemap_2_desugarer_transform()
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(param)
}

type Param =
  // Tag to unwrap when it is the first child.
  String

type InnerParam =
  Param

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
fn assertive_tests_data() -> List(core.AssertiveTestData(Param)) {
  [
    core.AssertiveTestData(
      param: "UnbridgeableTag",
      source: "
                <> Proof
                  <> UnbridgeableTag
                  <> UnbridgeableTag
                  <>
                    'some text'
                ",
      expected: "
                <> Proof
                  <>
                    'some text'
                ",
    ),
    core.AssertiveTestData(
      param: "UnbridgeableTag",
      source: "
                <> Proof
                  <> UnbridgeableTag
                    <> Granchild1
                    <> Granchild2
                  <> UnbridgeableTag
                    <> Granchild3
                  <>
                    'some text'
                ",
      expected: "
                <> Proof
                  <> Granchild1
                  <> Granchild2
                  <> UnbridgeableTag
                    <> Granchild3
                  <>
                    'some text'
                ",
    ),
    core.AssertiveTestData(
      param: "UnbridgeableTag",
      source: "
                <> Proof
                  <> UnbridgeableTag
                    <> UnbridgeableTag
                    <> Granchild2
                  <>
                    'some text'
                ",
      expected: "
                <> Proof
                  <> Granchild2
                  <>
                    'some text'
                ",
    ),
    core.AssertiveTestData(
      param: "UnbridgeableTag",
      source: "
                <> div
                  <> p
                    <>
                      'Text'
                  <> UnbridgeableTag
                  <>
                    'More'
                ",
      expected: "
                <> div
                  <> p
                    <>
                      'Text'
                  <> UnbridgeableTag
                  <>
                    'More'
                ",
    ),
    core.AssertiveTestData(
      param: "span",
      source: "
                <> div
                  <> span
                    <> span
                      <>
                        'Inside'
                ",
      expected: "
                <> div
                  <>
                    'Inside'
                ",
    ),
  ]
}

pub fn assertive_tests() {
  core.assertive_test_collection_from_data(
    name,
    assertive_tests_data(),
    constructor,
  )
}
