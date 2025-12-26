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
import on

fn nodemap(
  vxml: VXML,
  inner: InnerParam,
) -> Result(#(VXML, TrafficLight), DesugaringError) {
  case vxml {
    V(_, tag, attrs, children) if tag == inner.0 -> {
      use attr <- on.ok(
        infra.attrs_unique_key_or_none(attrs, inner.1)
      )

      use attr <- on.none_some(
        attr,
        fn() { Ok(#(vxml, Continue)) },
      )

      use first, rest <- on.empty_nonempty(
        children,
        fn() { Error(DesugaringError(vxml.blame, "first child missing")) },
      )

      case first {
        T(..) -> Error(DesugaringError(first.blame, "first child is text node instead of V-node"))
        V(..) -> {
          let first = first |> infra.v_start_insert_text(attr.val <> inner.2)
          Ok(#(V(..vxml, children: [first, ..rest]), inner.3))
        }
      }
    }
    _ -> Ok(#(vxml, Continue))
  }
}

fn nodemap_factory(inner: InnerParam) -> n2t.EarlyReturnOneToOneNodemap {
  nodemap(_, inner)
}

fn transform_factory(inner: InnerParam) -> DesugarerTransform {
  nodemap_factory(inner)
  |> n2t.early_return_one_to_one_nodemap_2_desugarer_transform
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(param)
}

type Param = #(String,  String,    String,     TrafficLight)
//             ↖        ↖          ↖           ↖
//             tag      key        connector   return early or not
//                                 string
type InnerParam = Param

pub const name = "insert_attribute_value_at_first_child_start"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// inserts text at the beginning and end of a
/// specified tag
pub fn constructor(param: Param) -> Desugarer {
  let assert Ok(inner) = param_to_inner_param(param)
  Desugarer(
    name: name,
    stringified_param: option.Some(ins(inner)),
    stringified_outside: option.None,
    transform: transform_factory(inner),
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
