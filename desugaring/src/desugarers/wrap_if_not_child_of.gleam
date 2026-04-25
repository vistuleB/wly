import gleam/option
import gleam/list
import gleam/string.{inspect as ins}
import infrastructure.{type Desugarer, Desugarer, type DesugarerTransform, type DesugaringError} as infra
import nodemaps_2_desugarer_transforms as n2t
import vxml.{type VXML, V}
import blame as bl

fn nodemap(
  vxml: VXML,
  ancestors: List(VXML),
  _previous_siblings_before_mapping: List(VXML),
  _previous_siblings_after_mapping: List(VXML),
  _following_siblings_before_mapping: List(VXML),
  inner: InnerParam,
) -> VXML {
  case vxml {
    V(_, tag, _, _) if tag == inner.0 -> {
      let parent_excluded = case list.first(ancestors) {
        Ok(V(_, t, _, _)) -> list.contains(inner.2, t)
        _ -> False
      }
      case parent_excluded {
        True -> vxml
        False -> V(desugarer_blame(25), inner.1, [], [vxml])
      }
    }
    _ -> vxml
  }
}

fn nodemap_factory(inner: InnerParam) -> n2t.FancyOneToOneNoErrorNodemap {
  fn(node, ancestors, prev_before, prev_after, following) {
    nodemap(node, ancestors, prev_before, prev_after, following, inner)
  }
}

fn transform_factory(inner: InnerParam) -> DesugarerTransform {
  nodemap_factory(inner)
  |> n2t.fancy_one_to_one_no_error_nodemap_2_desugarer_transform
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(param)
}

type Param = #(String,  String,     List(String))
//             ↖        ↖           ↖
//             tag to   tag to      ...if NOT child of
//             wrap     wrap with   any of these
type InnerParam = Param

pub const name = "wrap_if_not_child_of"
fn desugarer_blame(line_no: Int) { bl.Des([], name, line_no) }

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// Wraps each occurrence of a target tag in a new
/// parent tag, unless the target is a direct child
/// of one of the specified excluded parent tags.
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
      param: #("p", "wrapper", ["div"]),
      source:   "
                <> root
                  <> div
                    <> p
                      <>
                        'inside excluded'
                  <> section
                    <> p
                      <>
                        'inside allowed'
                ",
      expected: "
                <> root
                  <> div
                    <> p
                      <>
                        'inside excluded'
                  <> section
                    <> wrapper
                      <> p
                        <>
                          'inside allowed'
                ",
    ),
    infra.AssertiveTestData(
      param: #("span", "box", ["article", "aside"]),
      source:   "
                <> root
                  <> article
                    <> span
                      <>
                        'in article'
                  <> aside
                    <> span
                      <>
                        'in aside'
                  <> div
                    <> span
                      <>
                        'in div'
                ",
      expected: "
                <> root
                  <> article
                    <> span
                      <>
                        'in article'
                  <> aside
                    <> span
                      <>
                        'in aside'
                  <> div
                    <> box
                      <> span
                        <>
                          'in div'
                ",
    ),
  ]
}

pub fn assertive_tests() {
  infra.assertive_test_collection_from_data(name, assertive_tests_data(), constructor)
}
