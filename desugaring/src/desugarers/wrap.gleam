import gleam/option
import gleam/string.{inspect as ins}
import infrastructure.{type Desugarer, Desugarer, type DesugarerTransform, type DesugaringError} as infra
import nodemaps_2_desugarer_transforms as n2t
import vxml.{type VXML, V}
import blame as bl

fn nodemap(
  vxml: VXML,
  tag: String,
  wrapper: VXML,
) -> VXML {
  case vxml {
    V(_, t, _, _) if t == tag -> {
      let assert V(..) = wrapper
      V(..wrapper, children: [vxml])
    }
    _ -> vxml
  }
}

fn nodemap_factory(inner: InnerParam) -> n2t.OneToOneNoErrorNodeMap {
  nodemap(_, inner.0, inner.1)
}

fn transform_factory(inner: InnerParam) -> DesugarerTransform {
  nodemap_factory(inner)
  |> n2t.one_to_one_no_error_nodemap_2_desugarer_transform()
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(#(param.0, V(desugarer_blame(32), param.1, [], [])))
}

type Param = #(String,  String)
//             ↖        ↖
//             target   wrapper
//             tag      tag
type InnerParam = #(String, VXML)
fn desugarer_blame(line_no: Int) { bl.Des([], name, line_no) }

pub const name = "wrap"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// For a specified target tag, wraps the entire tag
/// inside a given wrapper tag.
///
/// Will create a wrapper around the target tag,
/// with the target tag as its only child.
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
      param: #("p", "wrapper"),
      source:   "
                <> root
                  <> div
                    <> p
                      <>
                        'Hello'
                    <> span
                      <>
                        'World'
                ",
      expected: "
                <> root
                  <> div
                    <> wrapper
                      <> p
                        <>
                          'Hello'
                    <> span
                      <>
                        'World'
                ",
    ),
    infra.AssertiveTestData(
      param: #("section", "container"),
      source:   "
                <> root
                  <> section
                    <> h1
                      <>
                        'Title'
                ",
      expected: "
                <> root
                  <> container
                    <> section
                      <> h1
                        <>
                          'Title'
                ",
    ),
    infra.AssertiveTestData(
      param: #("article", "main"),
      source:   "
                <> root
                  <> article
                    <> h1
                      <>
                        'Title'
                    <> footer
                      <>
                        'Footer'
                ",
      expected: "
                <> root
                  <> main
                    <> article
                      <> h1
                        <>
                          'Title'
                      <> footer
                        <>
                          'Footer'
                ",
    ),
    infra.AssertiveTestData(
      param: #("p", "wrapper"),
      source:   "
                <> root
                  <> div
                    <> p
                      <>
                        'First paragraph'
                    <> section
                      <> p
                        <>
                          'Second paragraph'
                      <> p
                        <>
                          'Third paragraph'
                ",
      expected: "
                <> root
                  <> div
                    <> wrapper
                      <> p
                        <>
                          'First paragraph'
                    <> section
                      <> wrapper
                        <> p
                          <>
                            'Second paragraph'
                      <> wrapper
                        <> p
                          <>
                            'Third paragraph'
                ",
    ),
  ]
}

pub fn assertive_tests() {
  infra.assertive_test_collection_from_data(name, assertive_tests_data(), constructor)
}
