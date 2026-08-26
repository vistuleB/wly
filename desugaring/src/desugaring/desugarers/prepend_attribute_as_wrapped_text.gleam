import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
}
import desugaring/nodemaps_2_transform as n2t
import gleam/option.{Some}
import gleam/string
import vxml.{type VXML, Attr, Line, T, V}
import vxml/blame as bl

pub const name = "prepend_attribute_as_wrapped_text"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Prepends a wrapped attribute value to every matching
/// element.
pub fn constructor(param: Param) -> Desugarer {
  authoring.desugarer(
    name: name,
    param: param,
    prepare: param_to_inner_param,
    transform: inner_param_to_transform,
  )
}

type Param =
  #(
    // Target tag.
    String,
    // Attribute key.
    String,
    // Wrapper node.
    VXML,
  )

type InnerParam =
  #(String, String, VXML, Int)

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(#(param.0, param.1, param.2, string.length(param.1)))
}

fn inner_param_to_transform(inner: InnerParam) -> DesugarerTransform {
  nodemap_factory(inner)
  |> n2t.one_to_one_no_error_nodemap_2_desugarer_transform()
}

fn nodemap_factory(inner: InnerParam) -> n2t.OneToOneNoErrorNodemap {
  nodemap(_, inner)
}

fn nodemap(vxml: VXML, inner: InnerParam) -> VXML {
  case vxml {
    V(_, tag, _, children) if tag == inner.0 -> {
      case core.v_first_attr_with_key(vxml, inner.1) {
        Some(Attr(blame, _, value)) if value != "" -> {
          let assert V(b, t, a, c) = inner.2
          let t_blame = bl.advance(blame, inner.3 + 1)
          let wrapped_text =
            V(b, t, a, [T(t_blame, [Line(t_blame, value)]), ..c])
          V(..vxml, children: [wrapped_text, ..children])
        }
        _ -> vxml
      }
    }
    _ -> vxml
  }
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊

fn assertive_tests_data() -> List(core.AssertiveTestData(Param)) {
  let wrapper =
    vxml.V(bl.no_blame, "span", [vxml.Attr(bl.no_blame, "class", "label")], [])
  [
    core.AssertiveTestData(
      param: #("div", "title", wrapper),
      source: "
                <> div
                  title='Hello World'
                  <> p
                    <>
                      'Content'
                ",
      expected: "
                <> div
                  title='Hello World'
                  <> span
                    class=label
                    <>
                      ''Hello World''
                  <> p
                    <>
                      'Content'
                ",
    ),
    core.AssertiveTestData(
      param: #("div", "missing", wrapper),
      source: "
                <> div
                  class='test'
                  <> p
                    <>
                      'Content'
                ",
      expected: "
                <> div
                  class='test'
                  <> p
                    <>
                      'Content'
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
