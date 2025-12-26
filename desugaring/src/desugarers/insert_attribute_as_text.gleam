import gleam/option.{Some}
import gleam/string.{inspect as ins}
import infrastructure.{type Desugarer, Desugarer, type DesugarerTransform, type DesugaringError} as infra
import nodemaps_2_desugarer_transforms as n2t
import vxml.{ type VXML, V, Attr}

fn nodemap(
  vxml: VXML,
  inner: InnerParam,
) -> VXML {
  case vxml {
    V(_, tag, _, _) if tag == inner.0 -> {
      case infra.v_first_attr_with_key(vxml, inner.1) {
        Some(Attr(_, _, value)) if value != "" ->
          infra.v_start_insert_text(vxml, value)
        _ -> vxml
      }
    }
    _ -> vxml
  }
}

fn nodemap_factory(inner: InnerParam) -> n2t.OneToOneNoErrorNodemap {
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
//             tag     attr key
type InnerParam = Param

pub const name = "insert_attribute_as_text"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// Given arguments
/// ```
/// tag, attr_key
/// ```
/// insert the value of the attr with key
/// 'attr_key' into the first line of the first
/// text node child of the tag, or else as a text
/// node unto itself if the first child is not a 
/// text node. If the attr doesn't exist, the node
/// is left unchanged. The attr value is used
/// as-is without any newline splitting. Empty
/// attr values are ignored.
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
                  title='Hello World'
                  <> p
                    <>
                      'Content'
                ",
      expected: "
                <> div
                  title='Hello World'
                  <>
                    ''Hello World''
                  <> p
                    <>
                      'Content'
                ",
    ),
    infra.AssertiveTestData(
      param: #("div", "missing"),
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
    infra.AssertiveTestData(
      param: #("section", "description"),
      source: "
                <> section
                  description='Line 1\\nLine 2\\nLine 3'
                  <> h1
                    <>
                      'Title'
                ",
      expected: "
                <> section
                  description='Line 1\\nLine 2\\nLine 3'
                  <>
                    ''Line 1\\nLine 2\\nLine 3''
                  <> h1
                    <>
                      'Title'
                ",
    ),
    infra.AssertiveTestData(
      param: #("span", "data"),
      source: "
                <> span
                  data=
                  <> em
                    <>
                      'Text'
                ",
      expected: "
                <> span
                  data=
                  <> em
                    <>
                      'Text'
                ",
    ),
    infra.AssertiveTestData(
      param: #("section", "title"),
      source: "
                <> div
                  <> section
                    title=Outer Section
                    <> section
                      title=Inner Section
                      <> p
                        <>
                          'Content'
                ",
      expected: "
                <> div
                  <> section
                    title=Outer Section
                    <>
                      'Outer Section'
                    <> section
                      title=Inner Section
                      <>
                        'Inner Section'
                      <> p
                        <>
                          'Content'
                ",
    ),
    infra.AssertiveTestData(
      param: #("item", "value"),
      source: "
                <> container
                  <> item
                    value=Parent
                    <> item
                      value=Child1
                      <> p
                        <>
                          'Text1'
                    <> item
                      value=Child2
                      <> p
                        <>
                          'Text2'
                    <> p
                      <>
                        'Parent Content'
                ",
      expected: "
                <> container
                  <> item
                    value=Parent
                    <>
                      'Parent'
                    <> item
                      value=Child1
                      <>
                        'Child1'
                      <> p
                        <>
                          'Text1'
                    <> item
                      value=Child2
                      <>
                        'Child2'
                      <> p
                        <>
                          'Text2'
                    <> p
                      <>
                        'Parent Content'
                ",
    ),
    infra.AssertiveTestData(
      param: #("item", "value"),
      source: "
                <> container
                  <> item
                    value=Parent
                    <> item
                      value=Child1
                      <>
                        'Text1'
                    <> item
                      value=Child2
                      <>
                        'Text2'
                    <> p
                      <>
                        'Parent Content'
                ",
      expected: "
                <> container
                  <> item
                    value=Parent
                    <>
                      'Parent'
                    <> item
                      value=Child1
                      <>
                        'Child1Text1'
                    <> item
                      value=Child2
                      <>
                        'Child2Text2'
                    <> p
                      <>
                        'Parent Content'
                ",
    ),
  ]
}

pub fn assertive_tests() {
  infra.assertive_test_collection_from_data(name, assertive_tests_data(), constructor)
}
