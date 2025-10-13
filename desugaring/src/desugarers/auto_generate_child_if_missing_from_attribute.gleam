import gleam/option
import gleam/string.{inspect as ins}
import infrastructure.{type Desugarer, Desugarer, type DesugarerTransform, type DesugaringError, type TrafficLight, Continue, GoBack} as infra
import nodemaps_2_desugarer_transforms as n2t
import vxml.{type VXML, V, T, Line}
import blame as bl
import on

fn nodemap(
  node: VXML,
  inner: InnerParam,
) -> #(VXML, TrafficLight) {
  let #(parent_tag, child_tag, attr_key) = inner
  case node {
    V(_, tag, _, _) if tag == parent_tag -> {
      // return early if we have a child of tag child_tag:
      use <- on.nonempty_empty(
        infra.v_children_with_tag(node, child_tag),
        fn(_, _) { #(node, GoBack) },
      )

      // return early if we don't have an attr of key attr_key:
      use attr, _ <- on.empty_nonempty(
        infra.v_attrs_with_key(node, attr_key),
        #(node, GoBack),
      )

      #(
        V(
          ..node,
          children: [
            V(
              desugarer_blame(33),
              child_tag,
              [],
              [T(attr.blame, [Line(attr.blame, attr.value)])],
            ),
            ..node.children,
          ]
        ),
        GoBack
      )
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

type Param = #(String, String, String)
//             ↖       ↖       ↖
//             parent  child   attr
//             tag     tag
type InnerParam = Param

pub const name = "auto_generate_child_if_missing_from_attribute"
fn desugarer_blame(line_no: Int) { bl.Des([], name, line_no) }

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// Given arguments
/// ```
/// parent_tag, child_tag, attr_key
/// ```
/// will, for each node of tag `parent_tag`,
/// generate, if the node has no existing children
/// tag `child_tag`, by using the value of
/// attr_key as the contents of the child of
/// tag child_tag. If no such attr exists, does
/// nothing to the node of tag parent_tag.
///
/// Early-returns from subtree rooted at parent_tag.
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
      param: #("Chapter", "ChapterTitle", "title"),
      source:   "
                  <> root
                    <> Chapter
                      title=Einleitung
                      <>
                        \"Chapter content\"
                    <> Chapter
                      title=Advanced Topics
                      <> ChapterTitle
                        <>
                          \"Existing title\"
                      <>
                        \"More content\"
                    <> Chapter
                      <>
                        \"No title attr\"
                    <> OtherElement
                      title=Should not change
                      <>
                        \"Other content\"
                ",
      expected: "
                  <> root
                    <> Chapter
                      title=Einleitung
                      <> ChapterTitle
                        <>
                          \"Einleitung\"
                      <>
                        \"Chapter content\"
                    <> Chapter
                      title=Advanced Topics
                      <> ChapterTitle
                        <>
                          \"Existing title\"
                      <>
                        \"More content\"
                    <> Chapter
                      <>
                        \"No title attr\"
                    <> OtherElement
                      title=Should not change
                      <>
                        \"Other content\"
                ",
    ),
    infra.AssertiveTestData(
      param: #("Sub", "SubTitle", "title"),
      source:   "
                  <> root
                    <> Sub
                      title=Overview
                      <>
                        \"Sub content\"
                    <> Sub
                      title=Details
                      <> SubTitle
                        <>
                          \"Existing subtitle\"
                      <>
                        \"More sub content\"
                    <> Sub
                      <>
                        \"No title attr\"
                    <> Chapter
                      title=Should not change
                      <>
                        \"Chapter content\"
                ",
      expected: "
                  <> root
                    <> Sub
                      title=Overview
                      <> SubTitle
                        <>
                          \"Overview\"
                      <>
                        \"Sub content\"
                    <> Sub
                      title=Details
                      <> SubTitle
                        <>
                          \"Existing subtitle\"
                      <>
                        \"More sub content\"
                    <> Sub
                      <>
                        \"No title attr\"
                    <> Chapter
                      title=Should not change
                      <>
                        \"Chapter content\"
                ",
    ),
  ]
}

pub fn assertive_tests() {
  infra.assertive_test_collection_from_data(name, assertive_tests_data(), constructor)
}
