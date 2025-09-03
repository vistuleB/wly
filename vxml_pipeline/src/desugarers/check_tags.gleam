import gleam/list
import gleam/option
import gleam/string.{inspect as ins}
import infrastructure.{type Desugarer, Desugarer, type DesugarerTransform, type DesugaringError, DesugaringError} as infra
import nodemaps_2_desugarer_transforms as n2t
import vxml.{type VXML, T, V}

fn nodemap(
  vxml: VXML,
  inner: InnerParam,
) -> Result(VXML, DesugaringError) {
  case vxml {
    T(_, _) -> Ok(vxml)
    V(blame, tag, _, _) -> {
      case list.contains(inner.0, tag) {
        True -> Ok(vxml)
        False -> Error(DesugaringError(
          blame,
          "tag '" <> tag <> "' is not in approved " <> inner.1 <> " list of tags: " <> ins(inner.0)
        ))
      }
    }
  }
}

fn nodemap_factory(inner: InnerParam) -> n2t.OneToOneNodeMap {
  nodemap(_, inner)
}

fn transform_factory(inner: InnerParam) -> DesugarerTransform {
  nodemap_factory(inner)
  |> n2t.one_to_one_nodemap_2_desugarer_transform()
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(param)
}

type Param = #(List(String), String)
//             ↖             ↖
//             approved      caller id
//             tags
type InnerParam = Param

pub const name = "check_tags"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// Validates that all tags in the document are
/// from an approved list of tags.
///
/// Returns a DesugaringError if any tag is found
/// that is not in the approved list.
///
/// Processes all nodes depth-first.
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
      param: #(["root", "div", "p", "span"], "test1"),
      source:   "
                <> root
                  <> div
                    <> p
                      <>
                        \"Hello\"
                    <> span
                      <>
                        \"World\"
                ",
      expected: "
                <> root
                  <> div
                    <> p
                      <>
                        \"Hello\"
                    <> span
                      <>
                        \"World\"
                ",
    ),
    infra.AssertiveTestData(
      param: #(["root", "section", "h1"], "test2"),
      source:   "
                <> root
                  <> section
                    <> h1
                      <>
                        \"Title\"
                ",
      expected: "
                <> root
                  <> section
                    <> h1
                      <>
                        \"Title\"
                ",
    ),
  ]
}

// Note: Error testing infrastructure is not available,
// so we only include assertive tests for valid cases.
// Invalid cases would result in DesugaringError at runtime.

pub fn assertive_tests() {
  infra.assertive_test_collection_from_data(name, assertive_tests_data(), constructor)
}
