import gleam/option
import gleam/string.{inspect as ins}
import infrastructure.{type Desugarer, Desugarer, type DesugarerTransform, type DesugaringError, type TrafficLight, Continue, GoBack} as infra
import nodemaps_2_desugarer_transforms as n2t
import vxml.{type VXML, V}

fn children_up_to_not_including(
  children: List(VXML),
  stop_tag: String,
  acc: List(VXML),
) -> #(List(VXML), List(VXML)) {
  case children {
    [] -> #([], [])
    [first, ..rest] -> {
      case first {
        V(_, tag, _, _) if tag == stop_tag -> #(acc, children)
        _ -> {
          let #(acc, rest) = children_up_to_not_including(rest, stop_tag, acc)
          #([first, ..acc], rest)
        }
      }
    }
  }
}

fn nodemap(
  node: VXML,
  inner: InnerParam,
) -> #(VXML, TrafficLight) {
  case node {
    V(blame, tag, _, children) if tag == inner.0 -> {
        let #(before, after) = children_up_to_not_including(children, inner.1, [])
        let children = [V(blame, inner.2, [], before), ..after]
        #(V(..node, children: children), GoBack)
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

type Param = #(String,  String,  String)
//             ↖        ↖        ↖
//             parent   stop     wrapper
//             tag      tag      tag
type InnerParam = Param

pub const name = "wrap_children_before_in"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// For a specified parent tag, wraps all children
/// from the first up to but not including the first
/// child with a specified "stop tag" into a given
/// wrapper tag.
///
/// Will create an empty wrapper in case the stop
/// tag is immediately encountered, or there are no
/// children.
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
  []
}

pub fn assertive_tests() {
  infra.assertive_test_collection_from_data(name, assertive_tests_data(), constructor)
}
