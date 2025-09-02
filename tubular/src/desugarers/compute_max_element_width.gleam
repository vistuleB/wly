import gleam/float
import gleam/list
import gleam/option.{Some, None}
import gleam/string.{inspect as ins}
import infrastructure.{type Desugarer, Desugarer, type DesugaringError, DesugaringError, type DesugarerTransform} as infra
import vxml.{type VXML, Attribute, T, V}
import nodemaps_2_desugarer_transforms as n2t
import on

fn v_before_transforming_children(
  node: VXML,
  state: Float,
  inner: InnerParam,
) -> Result(#(VXML, Float), DesugaringError) {
  let assert V(blame, tag, _, _) = node
  case list.contains(inner, tag) {
    False -> Ok(#(node, state))
    True -> {
      case infra.v_first_attribute_with_key(node, "width") {
        None -> Error(DesugaringError(blame, tag <> " tag must have width attribute"))
        Some(attr) -> {
          use #(width, _) <- on.error_ok(
            infra.parse_number_and_optional_css_unit(attr.value),
            on_error: fn(_) {
              Error(DesugaringError(attr.blame, "Could not parse digits in width attribute"))
            }
          )
          Ok(#(node, float.max(state, width)))
        }
      }
    }
  }
}

fn v_after_transforming_children(
  node: VXML,
  _: Float,
  state: Float,
) -> Result(#(VXML, Float), DesugaringError) {
  let assert V(_, tag, _, _) = node
  case tag == "Chapter" || tag == "Bootcamp" {
    False -> Ok(#(node, state))
    True -> {
      Ok(#(
        V(
          ..node,
          attributes: [
            Attribute(node.blame, "max-element-width", ins(state)),
            ..node.attributes
          ]
        ),
        0. // reset state for next article
      ))
    }
  }
}

fn nodemap_factory(inner: InnerParam) -> n2t.OneToOneBeforeAndAfterStatefulNodeMap(Float) {
   n2t.OneToOneBeforeAndAfterStatefulNodeMap(
    v_before_transforming_children: fn(node, state){
      v_before_transforming_children(node, state, inner)
    },
    v_after_transforming_children: v_after_transforming_children,
    t_nodemap: fn(node, state) {
      let assert T(_, _) = node
      Ok(#(node, state))
    },
  )
}

fn transform_factory(inner: InnerParam) -> DesugarerTransform {
  n2t.one_to_one_before_and_after_stateful_nodemap_2_desugarer_transform(nodemap_factory(inner), 0.)
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(param)
}

type Param = List(String)
//           ↖
//           tags to include in the 
//           max width calculation
type InnerParam = Param

pub const name = "compute_max_element_width"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// compute max element width
pub fn constructor(param: Param) -> Desugarer {
  Desugarer(
    name: name,
    stringified_param: option.None,
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