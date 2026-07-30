import gleam/list
import gleam/option
import desugaring/core.{type Desugarer, Desugarer, type DesugarerTransform, type DesugaringError} as core
import desugaring/nodemaps_2_transform as n2t
import vxml.{type VXML, T, V}

fn nodemap(
  vxml: VXML,
  ancestors: List(VXML),
  inner: InnerParam,
) -> List(VXML) {
  case vxml {
    T(_, _) -> [vxml]
    V(_, tag, _, children) -> {
      case core.use_list_pair_as_dict(inner, tag) {
        Error(Nil) -> [vxml]
        Ok(parent_tags) -> {
          case list.first(ancestors) {
            Error(Nil) -> [vxml]
            Ok(parent) -> {
              let assert V(_, actual_parent_tag, _, _) = parent
              case list.contains(parent_tags, actual_parent_tag) {
                False -> [vxml]
                True -> children
              }
            }
          }
        }
      }
    }
  }
}

fn nodemap_factory(inner: InnerParam) -> n2t.FancyOneToManyNoErrorNodemap {
  fn(node, ancestors, _, _, _) {
    nodemap(node, ancestors, inner)
  }
}

fn transform_factory(inner: InnerParam) -> DesugarerTransform {
  nodemap_factory(inner)
  |> n2t.fancy_one_to_many_no_error_nodemap_2_desugarer_transform()
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(param)
}

type Param = List(#(String,    List(String)))
//                  ↖          ↖
//                  tag to be  list of parent tag names
//                  unwrapped  that will cause child to unwrap
type InnerParam = Param

pub const name = "unwrap_if_child_of__batch"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// unwrap nodes based on parent-child
/// relationships
pub fn constructor(param: Param) -> Desugarer {
  Desugarer(
    name: name,
    stringified_param: option.Some(param |> core.list_param_stringifier),
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
  core.assertive_test_collection_from_data(name, assertive_tests_data(), constructor)
}
