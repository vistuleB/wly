import gleam/option
import gleam/string.{inspect as ins}
import infrastructure.{type Desugarer, Desugarer, type DesugarerTransform, type DesugaringError, type TrafficLight, Continue, GoBack} as infra
import nodemaps_2_desugarer_transforms as n2t
import vxml.{type VXML, V}

fn nodemap(
  vxml: VXML,
  inner: InnerParam,
) -> #(VXML, TrafficLight) {
  case vxml {
    V(blame, tag, attrs, children) if tag == inner.0 -> {
      case children {
        [first, ..rest] -> {
          let new_children = [V(blame, inner.1, [], [first]), ..rest]
          #(V(blame, tag, attrs, new_children), GoBack)
        }
        [] -> #(vxml, GoBack)
      }
    }
    _ -> #(vxml, Continue)
  }
}

fn nodemap_factory(inner: InnerParam) -> n2t.EarlyReturnOneToOneNoErrorNodemap {
  nodemap(_, inner)
}

fn transform_factory(inner: InnerParam) -> DesugarerTransform {
  nodemap_factory(inner)
  |> n2t.early_return_one_to_one_no_error_nodemap_2_desugarer_transform()
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(param)
}

type Param = #(String,    String)
//             ↖          ↖
//             parent     wrapper
//             tag
type InnerParam = Param

pub const name = "wrap_if_first_child_of"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// Wraps the first child of a specified node type with
/// a given wrapper.
///
/// Early-returns out of nodes of the specified tag.
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
      param: #("parent", "wrapper"),
      source: "
        <> parent
          <> child1
          <> child2
      ",
      expected: "
        <> parent
          <> wrapper
            <> child1
          <> child2
      ",
    ),
    infra.AssertiveTestData(
      param: #("parent", "wrapper"),
      source: "
        <> parent
      ",
      expected: "
        <> parent
      ",
    ),
    infra.AssertiveTestData(
      param: #("parent", "wrapper"),
      source: "
        <> parent
          <>
            'text node'
          <> child
      ",
      expected: "
        <> parent
          <> wrapper
            <>
              'text node'
          <> child
      ",
    ),
    infra.AssertiveTestData(
      param: #("parent", "wrapper"),
      source: "
        <> root
          <> parent
            <> child1
          <> parent
            <> child2
      ",
      expected: "
        <> root
          <> parent
            <> wrapper
              <> child1
          <> parent
            <> wrapper
              <> child2
      ",
    ),
  ]
}

pub fn assertive_tests() {
  infra.assertive_test_collection_from_data(name, assertive_tests_data(), constructor)
}
