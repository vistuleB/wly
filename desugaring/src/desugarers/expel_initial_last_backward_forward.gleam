import gleam/option
import gleam/list
import gleam/string.{inspect as ins}
import infrastructure.{type Desugarer, Desugarer, type DesugarerTransform, type DesugaringError} as infra
import nodemaps_2_desugarer_transforms as n2t
import vxml.{type VXML, V}

fn nodemap(
  node: VXML,
  inner: InnerParam,
) -> List(VXML) {
  case node {
    V(_, tag, _, children) if tag == inner.0 -> {
      let #(prefix, children) = infra.prefix_partition(children, infra.is_v_and_tag_is_one_of(_, inner.1))
      let #(children, suffix) = infra.suffix_partition(children, infra.is_v_and_tag_is_one_of(_, inner.2))
      [
        prefix,
        [V(..node, children: children)],
        suffix,
      ]
      |> list.flatten
    }
    _ -> [node]
  }
}

fn nodemap_factory(inner: InnerParam) -> n2t.OneToManyNoErrorNodemap {
  nodemap(_, inner)
}

fn transform_factory(inner: InnerParam) -> DesugarerTransform {
  nodemap_factory(inner)
  |> n2t.one_to_many_no_error_nodemap_2_desugarer_transform()
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(param)
}

type Param = #(String, List(String), List(String))
// for nodes of tag given by first string,
// cut-paste the prefix of children given by first list to before the node,
// and cut-paste the suffix of children given by second list to after the node
type InnerParam = Param

pub const name = "expel_initial_last_backward_forward"

//------------------------------------------------53
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
      param: #("A", ["B"], ["C"]),
      source:   "
                  <> Root
                    <> n1
                    <> A
                      <> B
                      <> B
                      <>
                        'text1'
                      <>
                        'text2'
                      <> C
                      <> C
                    <> A
                    <> B
                    <> A
                ",
      expected: "
                  <> Root
                    <> n1
                    <> B
                    <> B
                    <> A
                      <>
                        'text1'
                      <>
                        'text2'
                    <> C
                    <> C
                    <> A
                    <> B
                    <> A
                ",
    ),
    infra.AssertiveTestData(
      param: #("A", ["B", "C"], ["B", "C"]),
      source:   "
                  <> Root
                    <> A
                      <> B
                      <> B
                      <> C
                      <> C
                      <> mid
                      <> B
                      <> B
                      <> B
                      <> C
                ",
      expected: "
                  <> Root
                    <> B
                    <> B
                    <> C
                    <> C
                    <> A
                      <> mid
                    <> B
                    <> B
                    <> B
                    <> C
                ",
    ),
  ]
}

pub fn assertive_tests() {
  infra.assertive_test_collection_from_data(name, assertive_tests_data(), constructor)
}