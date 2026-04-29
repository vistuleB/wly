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
    V(_, tag, _, children) if tag == inner.0 -> {
      let node_to_prepend = case infra.v_first_attr_with_key(vxml, inner.1) {
        Some(Attr(_, _, value)) if value != "" -> {
          let assert V(b, t, a, c) = inner.2
          V(b, t, a, [
            T(
              desugarer_blame(18),
              [Line(desugarer_blame(19), value)]
            ),
            ..c
          ])
        }
        _ -> inner.3
      }
      V(..vxml, children: [node_to_prepend, ..children])
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

type Param = #(String, String,   VXML,   VXML)
//             ↖       ↖         ↖       ↖
//             tag     attr_key  wrapper else_node
type InnerParam = Param

pub const name = "prepend_attribute_wrapped_else_custom"
fn desugarer_blame(line_no: Int) { bl.Des([], name, line_no) }

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// Given arguments
/// ```
/// tag, attr_key, wrapper, else_node
/// ```
/// prepends a node to nodes of tag 'tag'. 
/// If the attribute 'attr_key' exists and is not empty,
/// the 'wrapper' node is used as a wrapper for the
/// attribute value (prepending it to its children). 
/// If the attribute doesn't exist or is empty,
/// 'else_node' is prepended instead.
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
  let wrapper = vxml.V(bl.no_blame, "span", [vxml.Attr(bl.no_blame, "class", "label")], [])
  let else_node = vxml.V(bl.no_blame, "span", [vxml.Attr(bl.no_blame, "class", "missing")], [vxml.T(bl.no_blame, [vxml.Line(bl.no_blame, "Default")])])
  [
    infra.AssertiveTestData(
      param: #("div", "title", wrapper, else_node),
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
    infra.AssertiveTestData(
      param: #("div", "missing", wrapper, else_node),
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
                  <> span
                    class=missing
                    <>
                      'Default'
                  <> p
                    <>
                      'Content'
                ",
    ),
  ]
}

pub fn assertive_tests() {
  infra.assertive_test_collection_from_data(name, assertive_tests_data(), constructor)
}