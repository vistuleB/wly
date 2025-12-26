import gleam/option
import gleam/string.{inspect as ins}
import infrastructure.{type Desugarer, Desugarer, type DesugarerTransform, type DesugaringError} as infra
import nodemaps_2_desugarer_transforms as n2t
import vxml.{type VXML, T, V}

fn update_children(
  children: List(VXML),
  inner: InnerParam, 
) -> List(VXML) {
  case children {
    [] -> []
    [one] -> [one]
    [T(..) as first, ..rest] -> [first, ..update_children(rest, inner)]
    [V(..) as first, ..rest] if first.tag != inner.1 -> [first, ..update_children(rest, inner)]
    [V(..) as first, T(..) as second, ..rest] -> [first, second, ..update_children(rest, inner)]
    [V(..) as first, V(..) as second, ..rest] if second.tag != inner.0 -> [first, ..update_children([second, ..rest], inner)]
    [V(..) as first, V(..) as second, ..rest]  -> {
      assert first.tag == inner.1
      assert second.tag == inner.0
      [
        V(
          ..second,
          children: [first, ..second.children],
        ),
        ..update_children(rest, inner)
      ]
    }
  }
}

fn nodemap(
  node: VXML,
  inner: InnerParam,
) -> VXML {
  case node {
    V(_, _, _, children) ->
      V(..node, children: update_children(children, inner))
    _ -> node
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

type Param = #(String, String) // first absorbs one instance no more of second, if adjacent siblings, by tag name
type InnerParam = Param

pub const name = "absorb_backward_one"

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
      param: #("B", "A"),
      source:   "
                  <> Root
                    <> n1
                      <> 
                        'text'
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
                        'text'
                    <> A
                    <> B
                      <> A
                    <> A
                    <> last
                ",
    ),
    infra.AssertiveTestData(
      param: #("B", "A"),
      source:   "
                  <> Root
                    <> n1
                      <> 
                        'text'
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
                        'text'
                    <> B
                      <> A
                    <> last
                    <> B
                    <> A
                ",
    ),
    infra.AssertiveTestData(
      param: #("B", "A"),
      source:   "
                  <> Root
                    <> n1
                      <> 
                        'text'
                    <> A
                    <> B
                    <> B
                    <> A
                    <> last
                    <> A
                    <> A
                    <> A
                    <> B
                    <> A
                ",
      expected: "
                  <> Root
                    <> n1
                      <> 
                        'text'
                    <> B
                      <> A
                    <> B
                    <> A
                    <> last
                    <> A
                    <> A
                    <> B
                      <> A
                    <> A
                ",
    ),
  ]
}

pub fn assertive_tests() {
  infra.assertive_test_collection_from_data(name, assertive_tests_data(), constructor)
}