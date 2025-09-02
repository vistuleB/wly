import gleam/option
import gleam/string.{inspect as ins}
import infrastructure.{type Desugarer, Desugarer, type DesugarerTransform, type DesugaringError, type TrafficLight, Continue, GoBack} as infra
import nodemaps_2_desugarer_transforms as n2t
import vxml.{type VXML, V}

fn nodemap(
  node: VXML,
  inner: InnerParam,
) -> #(VXML, TrafficLight) {
  case node {
    V(blame, tag, attrs, children) if tag == inner.0 -> {
      let wrapped_children = [V(blame, inner.1, [], children)]
      #(V(blame, tag, attrs, wrapped_children), GoBack)
    }
    _ -> #(node, Continue)
  }
}

fn nodemap_factory(inner: InnerParam) -> n2t.EarlyReturnOneToOneNoErrorNodeMap {
  nodemap(_, inner)
}

fn transform_factory(inner: InnerParam) -> DesugarerTransform {
  nodemap_factory(inner)
  |> n2t.early_return_one_to_one_no_error_nodemap_2_desugarer_transform()
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(param)
}

type Param = #(String,  String)
//             ↖        ↖
//             parent   wrapper
//             tag      tag
type InnerParam = Param

pub const name = "wrap_children_in"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// For a specified parent tag, wraps all children
/// in a given wrapper tag.
///
/// Will create a wrapper with all existing children
/// nested inside it.
///
/// Early-returns when it finds a node of the
/// specified parent tag to wrap.
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
      param: #("div", "wrapper"),
      source:   "
                <> root
                  <> div
                    <> p
                      <> div
                        <>
                          \"Hello\"
                    <> span
                      <>
                        \"World\"
                ",
      expected: "
                <> root
                  <> div
                    <> wrapper
                      <> p
                        <> div
                          <>
                            \"Hello\"
                      <> span
                        <>
                          \"World\"
                ",
    ),
    infra.AssertiveTestData(
      param: #("section", "content"),
      source:   "
                <> root
                  <> section
                ",
      expected: "
                <> root
                  <> section
                    <> content
                ",
    ),
    infra.AssertiveTestData(
      param: #("article", "body"),
      source:   "
                <> root
                  <> article
                    <> h1
                      <>
                        \"Title\"
                    <> footer
                      <>
                        \"Footer\"
                ",
      expected: "
                <> root
                  <> article
                    <> body
                      <> h1
                        <>
                          \"Title\"
                      <> footer
                        <>
                          \"Footer\"
                ",
    ),
  ]
}

pub fn assertive_tests() {
  infra.assertive_test_collection_from_data(name, assertive_tests_data(), constructor)
}
