import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError, Desugarer,
  DesugaringError,
}
import desugaring/nodemaps_2_transform as n2t
import gleam/float
import gleam/list
import gleam/option.{None, Some}
import gleam/string.{inspect as ins}
import on
import vxml.{type VXML, Attr, T, V}

fn on_enter(
  node: VXML,
  state: Float,
  inner: InnerParam,
) -> Result(#(VXML, Float), DesugaringError) {
  let assert V(blame, tag, _, _) = node
  case list.contains(inner, tag) {
    False -> Ok(#(node, state))
    True -> {
      case core.v_first_attr_with_key(node, "width") {
        None ->
          Error(DesugaringError(blame, tag <> " tag must have width attr"))
        Some(attr) -> {
          use #(width, _) <- on.error_ok(
            core.parse_number_and_optional_css_unit(attr.val),
            on_error: fn(_) {
              Error(DesugaringError(
                attr.blame,
                "Could not parse digits in width attr",
              ))
            },
          )
          Ok(#(node, float.max(state, width)))
        }
      }
    }
  }
}

fn on_exit(
  node: VXML,
  _: Float,
  state: Float,
) -> Result(#(VXML, Float), DesugaringError) {
  let assert V(_, tag, _, _) = node
  case tag == "Chapter" || tag == "Bootcamp" {
    False -> Ok(#(node, state))
    True -> {
      Ok(#(
        V(..node, attrs: [
          Attr(node.blame, "max-element-width", ins(state)),
          ..node.attrs
        ]),
        0.0,
        // reset state for next article
      ))
    }
  }
}

fn nodemap_factory(
  inner: InnerParam,
) -> n2t.OneToOneEnterExitStatefulNodemap(Float) {
  n2t.OneToOneEnterExitStatefulNodemap(
    on_enter: fn(node, state) { on_enter(node, state, inner) },
    on_exit: on_exit,
    on_text: fn(node, state) {
      let assert T(_, _) = node
      Ok(#(node, state))
    },
  )
}

fn transform_factory(inner: InnerParam) -> DesugarerTransform {
  nodemap_factory(inner)
  |> n2t.one_to_one_enter_exit_stateful_nodemap_2_desugarer_transform(0.0)
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(param)
}

type Param =
  List(String)

//           ↖
//           tags to include in the
//           max width calculation
type InnerParam =
  Param

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
fn assertive_tests_data() -> List(core.AssertiveTestData(Param)) {
  []
}

pub fn assertive_tests() {
  core.assertive_test_collection_from_data(
    name,
    assertive_tests_data(),
    constructor,
  )
}
