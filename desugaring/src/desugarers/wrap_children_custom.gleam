import gleam/option
import gleam/string.{inspect as ins}
import infrastructure.{
  type Desugarer,
  type DesugarerTransform,
  type DesugaringError,
  type TrafficLight,
  DesugaringError,
  Desugarer,
  Continue,
} as infra
import nodemaps_2_desugarer_transforms as n2t
import vxml.{type VXML, V, T}
import blame as bl

fn nodemap(
  node: VXML,
  inner: InnerParam,
) -> #(VXML, TrafficLight) {
  case node {
    V(_, tag, _, children) if tag == inner.0 -> {
      let q = inner.1
      let assert V(_, _, _, _) = q
      #(V(..node, children: [V(..q, children: children)]), inner.2)
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
  case param.1 {
    V(_, _, _, []) -> Ok(param)
    V(..) -> Error(DesugaringError(bl.no_blame, "given wrapper already has children"))
    T(..) -> Error(DesugaringError(bl.no_blame, "expecting V-node as wrapper"))
  }
}

type Param = #(String,  VXML,     TrafficLight)
//             ↖        ↖         ↖
//             parent   wrapper   early-return
//             tag                or not
type InnerParam = Param

pub const name = "wrap_children_custom"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// For a specified parent tag, wraps all children
/// in a given wrapper given by a vxml element.
///
/// Throws a DesugaringError if the wrapper is not a
/// V-node or already has children.
///
/// Early-returns after wrapping the children of a
/// node depending on the third argument.
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
