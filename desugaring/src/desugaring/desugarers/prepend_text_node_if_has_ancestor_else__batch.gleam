import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
}
import desugaring/nodemaps_2_transform as n2t
import gleam/list
import gleam/string
import vxml.{type VXML, Line, T, V}

pub const name = "prepend_text_node_if_has_ancestor_else__batch"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Prepends one of two texts according to whether each
/// target has the configured ancestor.
pub fn constructor(param: Param) -> Desugarer {
  authoring.desugarer(
    name: name,
    param: param,
    prepare: param_to_inner_param,
    transform: inner_param_to_transform,
  )
}

type Param =
  List(
    #(
      // Target tag.
      String,
      // Ancestor tag.
      String,
      // Text used inside the ancestor.
      String,
      // Text used outside the ancestor.
      String,
    ),
  )

type InnerParam =
  List(#(String, #(String, String, String)))

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  param
  |> core.quads_to_pairs
  |> Ok
}

fn inner_param_to_transform(inner: InnerParam) -> DesugarerTransform {
  nodemap_factory(inner)
  |> n2t.fancy_one_to_one_no_error_nodemap_2_desugarer_transform()
}

fn nodemap_factory(inner: InnerParam) -> n2t.FancyOneToOneNoErrorNodemap {
  fn(vxml, ancestors, _, _, _) { nodemap(vxml, ancestors, inner) }
}

fn nodemap(vxml: VXML, ancestors: List(VXML), inner: InnerParam) -> VXML {
  case vxml {
    T(_, _) -> vxml
    V(blame, tag, attrs, children) -> {
      case core.use_list_pair_as_dict(inner, tag) {
        Ok(#(ancestor_tag, if_version, else_version)) -> {
          let ancestor_tags = ancestors |> list.map(core.v_get_tag)
          let text = case list.contains(ancestor_tags, ancestor_tag) {
            True -> if_version
            False -> else_version
          }
          let contents = string.split(text, "\n")
          let new_text_node =
            T(blame, list.map(contents, fn(content) { Line(blame, content) }))
          V(blame, tag, attrs, [new_text_node, ..children])
        }
        Error(Nil) -> vxml
      }
    }
  }
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊

fn assertive_tests_data() -> List(core.AssertiveTestData(Param)) {
  [
    core.AssertiveTestData(
      param: [#("ze_tag", "ze_ancestor", "_if_text_", "_else_text_")],
      source: "
                <> root
                  <> ze_tag
                    <>
                      'some text V1'
                  <> ze_ancestor
                    <> distraction
                      <> ze_tag
                        <>
                          'some text V2'
                  <> ze_tag
                    <> AnotherNode
                      a=b
                ",
      expected: "
                <> root
                  <> ze_tag
                    <>
                      '_else_text_'
                    <>
                      'some text V1'
                  <> ze_ancestor
                    <> distraction
                      <> ze_tag
                        <>
                          '_if_text_'
                        <>
                          'some text V2'
                  <> ze_tag
                    <>
                      '_else_text_'
                    <> AnotherNode
                      a=b
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
