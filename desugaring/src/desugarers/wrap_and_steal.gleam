import gleam/list
import gleam/option
import gleam/string.{inspect as ins}
import infrastructure.{type Desugarer, Desugarer, type DesugarerTransform, type DesugaringError} as infra
import nodemaps_2_desugarer_transforms as n2t
import vxml.{type VXML, V}
import blame as bl

fn nodemap(
  vxml: VXML,
  inner: InnerParam,
) -> VXML {
  case vxml {
    V(_, t, _, children) if t == inner.0 -> {
      let wrapper = inner.1
      let assert V(..) = wrapper
      let #(above, children) = list.partition(children, infra.is_v_and_tag_is_one_of(_, inner.2))
      let #(below, children) = list.partition(children, infra.is_v_and_tag_is_one_of(_, inner.3))
      let vxml = V(..vxml, children: children)
      V(..wrapper, children: [above, [vxml], below] |> list.flatten)
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
  Ok(#(param.0, V(desugarer_blame(36), param.1, [], []), param.2, param.3))
}

type Param = #(String,  String,    List(String),           List(String))
//             ↖        ↖          ↖                       ↖
//             target   wrapper    list of names of        same, but dump
//             tag      tag        children for children   below the node
//                                 to steal and dump       
//                                 above node in wrapper   
type InnerParam = #(String, VXML, List(String), List(String))
fn desugarer_blame(line_no: Int) { bl.Des([], name, line_no) }

pub const name = "wrap_and_steal"

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
      param: #("p", "wrapper", ["mister"], []),
      source:   "
                <> root
                  <> div
                    <> p
                      <> none
                      <>
                        'Hello'
                      <> mister
                    <> span
                      <>
                        'World'
                ",
      expected: "
                <> root
                  <> div
                    <> wrapper
                      <> mister
                      <> p
                        <> none
                        <>
                          'Hello'
                    <> span
                      <>
                        'World'
                ",
    ),
    infra.AssertiveTestData(
      param: #("section", "container", [], ["mister"]),
      source:   "
                <> root
                  <> section
                    <> mister
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
                    <> mister
                ",
    ),
    infra.AssertiveTestData(
      param: #("article", "main", [], ["mister"]),
      source:   "
                <> root
                  <> article
                    <> mister
                    <> none
                    <> mister
                    <> none
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
                      <> none
                      <> none
                      <> h1
                        <>
                          'Title'
                      <> footer
                        <>
                          'Footer'
                    <> mister
                    <> mister
                ",
    ),
    infra.AssertiveTestData(
      param: #("p", "wrapper", ["a"], ["b"]),
      source:   "
                <> root
                  <> div
                    <> p
                      <> b
                      <> a
                      <> b
                      <>
                        'First paragraph'
                      <> a
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
                      <> a
                      <> a
                      <> p
                        <>
                          'First paragraph'
                      <> b
                      <> b
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
