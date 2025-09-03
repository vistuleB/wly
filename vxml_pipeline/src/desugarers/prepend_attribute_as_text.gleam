import gleam/option.{Some}
import gleam/string.{inspect as ins}
import infrastructure.{type Desugarer, Desugarer, type DesugarerTransform, type DesugaringError} as infra
import nodemaps_2_desugarer_transforms as n2t
import vxml.{ type VXML, TextLine, T, V, Attribute}
import blame as bl

fn nodemap(
  vxml: VXML,
  inner: InnerParam,
) -> VXML {
  case vxml {
    V(_, tag, _, children) if tag == inner.0 -> {
      case infra.v_first_attribute_with_key(vxml, inner.1) {
        Some(Attribute(_, _, value)) if value != "" ->
          V(..vxml, children: [
            T(
              desugarer_blame(18),
              [TextLine(desugarer_blame(19), value)]
            ),
            ..children
          ])
        _ -> vxml
      }
    }
    _ -> vxml
  }
}

fn nodemap_factory(inner: InnerParam) -> n2t.OneToOneNoErrorNodeMap {
  nodemap(_, inner)
}

fn transform_factory(inner: InnerParam) -> DesugarerTransform {
  nodemap_factory(inner)
  |> n2t.one_to_one_no_error_nodemap_2_desugarer_transform()
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(param)
}

type Param = #(String, String)
//             ↖       ↖
//             tag     attribute_key
type InnerParam = Param

pub const name = "prepend_attribute_as_text"
fn desugarer_blame(line_no: Int) {bl.Des([], name, line_no)}

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// Given arguments
/// ```
/// tag, attribute_key
/// ```
/// prepends the value of the attribute with key
/// 'attribute_key' as a text node to nodes of tag
/// 'tag'. If the attribute doesn't exist, the node
/// is left unchanged. The attribute value is used
/// as-is without any newline splitting. Empty
/// attribute values are ignored.
///
/// Processes all matching nodes depth-first.
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
      param: #("div", "title"),
      source: "
                <> div
                  title=\"Hello World\"
                  <> p
                    <>
                      \"Content\"
                ",
      expected: "
                <> div
                  title=\"Hello World\"
                  <>
                    \"\"Hello World\"\"
                  <> p
                    <>
                      \"Content\"
                ",
    ),
    infra.AssertiveTestData(
      param: #("div", "missing"),
      source: "
                <> div
                  class=\"test\"
                  <> p
                    <>
                      \"Content\"
                ",
      expected: "
                <> div
                  class=\"test\"
                  <> p
                    <>
                      \"Content\"
                ",
    ),
    infra.AssertiveTestData(
      param: #("section", "description"),
      source: "
                <> section
                  description=\"Line 1\\nLine 2\\nLine 3\"
                  <> h1
                    <>
                      \"Title\"
                ",
      expected: "
                <> section
                  description=\"Line 1\\nLine 2\\nLine 3\"
                  <>
                    \"\"Line 1\\nLine 2\\nLine 3\"\"
                  <> h1
                    <>
                      \"Title\"
                ",
    ),
    infra.AssertiveTestData(
      param: #("span", "data"),
      source: "
                <> span
                  data=
                  <> em
                    <>
                      \"Text\"
                ",
      expected: "
                <> span
                  data=
                  <> em
                    <>
                      \"Text\"
                ",
    ),
    infra.AssertiveTestData(
      param: #("section", "title"),
      source: "
                <> div
                  <> section
                    title=\"Outer Section\"
                    <> section
                      title=\"Inner Section\"
                      <> p
                        <>
                          \"Content\"
                ",
      expected: "
                <> div
                  <> section
                    title=\"Outer Section\"
                    <>
                      \"\"Outer Section\"\"
                    <> section
                      title=\"Inner Section\"
                      <>
                        \"\"Inner Section\"\"
                      <> p
                        <>
                          \"Content\"
                ",
    ),
    infra.AssertiveTestData(
      param: #("item", "value"),
      source: "
                <> container
                  <> item
                    value=\"Parent\"
                    <> item
                      value=\"Child1\"
                      <> p
                        <>
                          \"Text1\"
                    <> item
                      value=\"Child2\"
                      <> p
                        <>
                          \"Text2\"
                    <> p
                      <>
                        \"Parent Content\"
                ",
      expected: "
                <> container
                  <> item
                    value=\"Parent\"
                    <>
                      \"\"Parent\"\"
                    <> item
                      value=\"Child1\"
                      <>
                        \"\"Child1\"\"
                      <> p
                        <>
                          \"Text1\"
                    <> item
                      value=\"Child2\"
                      <>
                        \"\"Child2\"\"
                      <> p
                        <>
                          \"Text2\"
                    <> p
                      <>
                        \"Parent Content\"
                ",
    ),
  ]
}

pub fn assertive_tests() {
  infra.assertive_test_collection_from_data(name, assertive_tests_data(), constructor)
}
