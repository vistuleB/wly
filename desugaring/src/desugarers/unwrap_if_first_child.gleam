import gleam/option
import gleam/list
import gleam/string.{inspect as ins}
import infrastructure.{type Desugarer, Desugarer, type DesugarerTransform, type DesugaringError} as infra
import nodemaps_2_desugarer_transforms as n2t
import vxml.{type VXML, V}

fn filter_children(
  children: List(VXML),
  inner: InnerParam
) -> List(VXML) {
  case children {
    [V(_, tag, _, grandchildren), ..more] if tag == inner -> case grandchildren {
      [] -> filter_children(more, inner)
      _ -> filter_children(list.append(grandchildren, more), inner)
    }
    _ -> children
  }
}

fn nodemap(
  node: VXML,
  inner: InnerParam,
) -> #(VXML, infra.TrafficLight) {
  case node {
    V(_, _, _, children) -> #(V(..node, children: filter_children(children, inner)), infra.Continue)
    _ -> #(node, infra.Continue)
  }
}

fn nodemap_factory(inner: InnerParam) -> n2t.EarlyReturnOneToOneNoErrorNodemap {
  nodemap(_, inner)
}

fn transform_factory(inner: InnerParam) -> DesugarerTransform {
  nodemap_factory(inner)
  |> n2t.early_return_one_to_one_no_error_nodemap_2_desugarer_transform()
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(param)
}

type Param = String
//           ↖
//           tag to be unwrapped if it's the first child
type InnerParam = Param

pub const name = "unwrap_if_first_child"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// Unwraps a given tag when it occurs as the first
/// child of its parent, replacing the tag by its
/// children or just deleting it, and recurses by
/// treating re-processing the parent so that if the
/// same tag is found again as the first child it
/// will unwrap it again, etc.
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
      param: "WriterlyBlankLine",
      source: "
                <> Proof
                  <> WriterlyBlankLine
                  <> WriterlyBlankLine
                  <>
                    'some text'
                ",
      expected: "
                <> Proof
                  <>
                    'some text'
                ",
    ),
    infra.AssertiveTestData(
      param: "WriterlyBlankLine",
      source: "
                <> Proof
                  <> WriterlyBlankLine
                    <> Granchild1
                    <> Granchild2
                  <> WriterlyBlankLine
                    <> Granchild3
                  <>
                    'some text'
                ",
      expected: "
                <> Proof
                  <> Granchild1
                  <> Granchild2
                  <> WriterlyBlankLine
                    <> Granchild3
                  <>
                    'some text'
                ",
    ),
    infra.AssertiveTestData(
      param: "WriterlyBlankLine",
      source: "
                <> Proof
                  <> WriterlyBlankLine
                    <> WriterlyBlankLine
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
    infra.AssertiveTestData(
      param: "WriterlyBlankLine",
      source: "
                <> div
                  <> p
                    <>
                      'Text'
                  <> WriterlyBlankLine
                  <>
                    'More'
                ",
      expected: "
                <> div
                  <> p
                    <>
                      'Text'
                  <> WriterlyBlankLine
                  <>
                    'More'
                ",
    ),
    infra.AssertiveTestData(
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
  infra.assertive_test_collection_from_data(name, assertive_tests_data(), constructor)
}
