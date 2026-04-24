import gleam/option
import gleam/list
import gleam/string.{inspect as ins}
import infrastructure.{type Desugarer, Desugarer, type DesugarerTransform, type DesugaringError} as infra
import nodemaps_2_desugarer_transforms as n2t
import vxml.{type VXML, Line, T, V}
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
    V(_, tag, _, children) if tag == inner.0 ->
      case inner.2(vxml, ancestors, previous_siblings_before_mapping, previous_siblings_after_mapping, following_siblings_before_mapping) {
        True -> V(..vxml, children: [inner.1, ..children])
        False -> vxml
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
  let blame = desugarer_blame(39)
  #(
    param.0,
    T(
      blame,
      param.1
      |> string.split("\n")
      |> list.map(Line(blame, _))
    ),
    param.2,
  )
  |> Ok
}

type Param = #(String, String, infra.FancyConditionFn)
//             ↖       ↖       ↖
//             tag     text    condition
type InnerParam = #(String, VXML, infra.FancyConditionFn)

pub const name = "prepend_text_node_if_fancy"
fn desugarer_blame(line_no: Int) { bl.Des([], name, line_no) }

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// Same as prepend_text_node but with a fancy
/// condition function — only prepends the text node
/// when the condition returns True.
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
