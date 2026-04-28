import gleam/list
import gleam/option.{Some}
import gleam/string.{inspect as ins}
import infrastructure.{type Desugarer, Desugarer, type DesugarerTransform, type DesugaringError} as infra
import nodemaps_2_desugarer_transforms as n2t
import vxml.{ type VXML, Line, T, V, Attr}
import blame as bl

fn nodemap(
  vxml: VXML,
  inner: InnerParam,
) -> VXML {
  case vxml {
    V(blame, tag, _, children) if tag == inner.0 -> {
      case infra.v_first_attr_with_key(vxml, inner.1) {
        Some(Attr(_, _, value)) if value != "" -> {
          let line = Line(desugarer_blame(18), value)
          let children = case list.any(children, infra.is_text_node) {
            True -> {
              let #(before, after) =
                list.split_while(children, fn(c) { !infra.is_text_node(c) })
              let assert [first_t, ..rest] = after
              list.append(before, [infra.t_start_insert_line(first_t, line), ..rest])
            }
            False -> [T(blame, [line]), ..children]
          }
          V(..vxml, children: children)
        }
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
//             tag     attr_key
type InnerParam = Param

pub const name = "prepend_attribute_as_first_line"
fn desugarer_blame(line_no: Int) { bl.Des([], name, line_no) }

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// Given arguments
/// ```
/// tag, attr_key
/// ```
/// finds nodes of tag 'tag', and prepends
/// the value of the attr with key 'attr_key'
/// as the first line of the first text node child.
/// If no text node exists, one is created as the 
/// first child.If the attr doesn't exist, the node 
/// is left unchanged. Empty attr values are 
/// ignored. Processes all matching nodes 
/// depth-first.
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
      param: #("div", "title"),
      source: "
                <> div
                  title='Title'
                  <>
                    'Existing'
                ",
      expected: "
                <> div
                  title='Title'
                  <>
                    ''Title''
                    'Existing'
                ",
    ),
    infra.AssertiveTestData(
      param: #("div", "title"),
      source: "
                <> div
                  title='Title'
                  <> p
                    <>
                      'Inner'
                  <>
                    'Outer'
                ",
      expected: "
                <> div
                  title='Title'
                  <> p
                    <>
                      'Inner'
                  <>
                    ''Title''
                    'Outer'
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
                    value='Parent'
                    <> item
                      value=Child1
                      <> p
                        <>
                          'Text1'
                    <> p
                      <>
                        'Parent Content'
                ",
      expected: "
                <> container
                  <> item
                    value='Parent'
                    <>
                      ''Parent''
                    <> item
                      value=Child1
                      <>
                        'Child1'
                      <> p
                        <>
                          'Text1'
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
