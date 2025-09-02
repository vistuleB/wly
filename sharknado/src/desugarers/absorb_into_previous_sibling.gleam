import gleam/list
import gleam/option
import gleam/string.{inspect as ins}
import infrastructure.{type Desugarer, Desugarer, type DesugarerTransform, type DesugaringError} as infra
import nodemaps_2_desugarer_transforms as n2t
import vxml.{type VXML, T, V}

fn update_children(
  already_processed: List(VXML),
  previous_sibling: VXML,
  remaining: List(VXML),
  inner: InnerParam,
) -> List(VXML) {
  case remaining {
    [] -> [previous_sibling, ..already_processed] |> list.reverse
    [T(_, _) as first, ..rest] -> update_children([previous_sibling, ..already_processed], first, rest, inner)
    [V(_, tag, _, _) as first, ..rest] -> case previous_sibling {
      T(_, _) -> update_children([previous_sibling, ..already_processed], first, rest, inner)
      V(_, prev_tag, _, _) -> case list.contains(inner, tag) && !{ list.contains(inner, prev_tag) } {
        False -> update_children([previous_sibling, ..already_processed], first, rest, inner)
        True -> update_children(
          already_processed,
          V(..previous_sibling, children: list.append(previous_sibling.children, [first])),
          rest,
          inner,
        )
      }
    }
  }
}

fn nodemap(
  node: VXML,
  inner: InnerParam,
) -> VXML {
  case node {
    V(_, _, _, [first, second, ..rest]) ->
      V(..node, children: update_children([], first, [second, ..rest], inner))
    _ -> node
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
  Ok(param)
}

type Param = List(String)
type InnerParam = Param

pub const name = "absorb_into_previous_sibling"

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
      param: ["A", "B"],
      source:   "
                  <> Root
                    <> n1
                      <> 
                        \"text\"
                    <> A
                    <> A
                    <> B
                    <> A
                    <> last
                ",
      expected: "
                  <> Root
                    <> n1
                      <> 
                        \"text\"
                      <> A
                      <> A
                      <> B
                      <> A
                    <> last
                ",
    ),
    infra.AssertiveTestData(
      param: ["A", "B"],
      source:   "
                  <> Root
                    <> n1
                      <> 
                        \"text\"
                    <> A
                    <> B
                    <> last
                    <> B
                    <> A
                ",
      expected: "
                  <> Root
                    <> n1
                      <> 
                        \"text\"
                      <> A
                      <> B
                    <> last
                      <> B
                      <> A
                ",
    ),
  ]
}

pub fn assertive_tests() {
  infra.assertive_test_collection_from_data(name, assertive_tests_data(), constructor)
}