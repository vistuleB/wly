import gleam/list
import gleam/option
import gleam/string
import infrastructure.{type Desugarer, Desugarer, type DesugarerTransform, type DesugaringError} as infra
import nodemaps_2_desugarer_transforms as n2t
import vxml.{ type VXML, TextLine, T, V }

fn nodemap(
  vxml: VXML,
  ancestors: List(VXML),
  inner: InnerParam,
) -> VXML {
  case vxml {
    T(_, _) -> vxml
    V(blame, tag, attrs, children) -> {
      case infra.use_list_pair_as_dict(inner, tag) {
        Ok(#(ancestor_tag, if_version, else_version)) -> {
          let ancestor_tags = ancestors |> list.map(infra.v_get_tag)
          let text = case list.contains(ancestor_tags, ancestor_tag) {
            True -> if_version
            False -> else_version
          }
          let contents = string.split(text, "\n")
          let new_text_node =
            T(
              blame,
              list.map(
                contents,
                fn (content) { TextLine(blame, content) }
              )
            )
          V(blame, tag, attrs, [new_text_node, ..children])
        }
        Error(Nil) -> vxml
      }
    }
  }
}

fn nodemap_factory(inner: InnerParam) -> n2t.FancyOneToOneNoErrorNodeMap {
  fn(vxml, ancestors, _, _, _) {
    nodemap(vxml, ancestors, inner)
  }
}

fn transform_factory(inner: InnerParam) -> DesugarerTransform {
  nodemap_factory(inner)
  |> n2t.fancy_one_to_one_no_error_nodemap_2_desugarer_transform()
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  param
  |> infra.quads_to_pairs
  |> Ok
}

type Param =
  List(#(String, String,    String,      String))
//       ↖       ↖          ↖            ↖
//       tag     ancestor   if_version   else_version

type InnerParam =
  List(#(String, #(String, String, String)))

pub const name = "prepend_text_node_if_has_ancestor_else__batch"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// prepend one of two specified text fragments to
/// nodes of a certain tag depending on wether the
/// node has an ancestor of specified type or not
pub fn constructor(param: Param) -> Desugarer {
  Desugarer(
    name: name,
    stringified_param: option.Some(param |> infra.list_param_stringifier),
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
      param: [#("ze_tag", "ze_ancestor", "_if_text_", "_else_text_")],
      source:   "
                <> root
                  <> ze_tag
                    <>
                      \"some text V1\"
                  <> ze_ancestor
                    <> distraction
                      <> ze_tag
                        <>
                          \"some text V2\"
                  <> ze_tag
                    <> AnotherNode
                      a=b
                ",
      expected: "
                <> root
                  <> ze_tag
                    <>
                      \"_else_text_\"
                    <>
                      \"some text V1\"
                  <> ze_ancestor
                    <> distraction
                      <> ze_tag
                        <>
                          \"_if_text_\"
                        <>
                          \"some text V2\"
                  <> ze_tag
                    <>
                      \"_else_text_\"
                    <> AnotherNode
                      a=b
                ",
    ),
  ]
}

pub fn assertive_tests() {
  infra.assertive_test_collection_from_data(name, assertive_tests_data(), constructor)
}
