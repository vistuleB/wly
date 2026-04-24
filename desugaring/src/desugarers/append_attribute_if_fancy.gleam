import gleam/list
import gleam/option
import gleam/string.{inspect as ins}
import infrastructure.{
  type Desugarer,
  type DesugarerTransform,
  type DesugaringError,
  Desugarer,
} as infra
import nodemaps_2_desugarer_transforms as n2t
import vxml.{
  type Attr,
  type VXML,
  Attr,
  V,
}
import blame as bl

fn nodemap(
  vxml: VXML,
  ancestors: List(VXML),
  previous_siblings_before_mapping: List(VXML),
  previous_siblings_after_mapping: List(VXML),
  following_siblings_before_mapping: List(VXML),
  inner: InnerParam,
) -> VXML {
  case vxml {
    V(_, tag, attrs, _) if tag == inner.0 -> {
      case inner.1(vxml, ancestors, previous_siblings_before_mapping, previous_siblings_after_mapping, following_siblings_before_mapping) {
        True -> V(..vxml, attrs: list.append(attrs, [inner.2]))
        False -> vxml
      }
    }
    _ -> vxml
  }
}

fn nodemap_factory(inner: InnerParam) -> n2t.FancyOneToOneNoErrorNodemap {
  fn(node, ancestors, previous_siblings_before_mapping, previous_siblings_after_mapping, following_siblings_before_mapping) {
    nodemap(node, ancestors, previous_siblings_before_mapping, previous_siblings_after_mapping, following_siblings_before_mapping, inner)
  }
}

fn transform_factory(inner: InnerParam) -> DesugarerTransform {
  nodemap_factory(inner)
  |> n2t.fancy_one_to_one_no_error_nodemap_2_desugarer_transform
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  #(
    param.0,
    param.1,
    Attr(desugarer_blame(54), param.2, param.3),
  )
  |> Ok
}

type Param = #(String, fn(VXML, List(VXML), List(VXML), List(VXML), List(VXML)) -> Bool, String, String)
//             ↖ tag   ↖ condition                                                       ↖ attr  ↖ value   ↖ early return or not
type InnerParam = #(String, fn(VXML, List(VXML), List(VXML), List(VXML), List(VXML)) -> Bool, Attr)

pub const name = "append_attribute_if"
fn desugarer_blame(line_no: Int) { bl.Des([], name, line_no) }

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// append an attribute to a given tag if the node
/// meets a condition
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
  ]
}

pub fn assertive_tests() {
  infra.assertive_test_collection_from_data(name, assertive_tests_data(), constructor)
}
