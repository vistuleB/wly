import gleam/list
import gleam/option
import gleam/string.{inspect as ins}
import infrastructure.{type Desugarer, Desugarer, type DesugarerTransform, type DesugaringError} as infra
import nodemaps_2_desugarer_transforms as n2t
import vxml.{type VXML, V}

fn nodemap(
  node: VXML,
  ancestors: List(VXML),
  inner: InnerParam,
) -> List(VXML) {
  case node {
    V(_, tag, _, children) ->
      case infra.use_list_pair_as_dict(inner, tag) {
        Error(Nil) -> [node]
        Ok(forbidden) -> {
          let ancestor_names = list.map(ancestors, infra.v_get_tag)
          case list.any(ancestor_names, list.contains(forbidden, _)) {
            True -> children
            False -> [node]
          }
        }
      }
    _ -> [node]
  }
}

fn nodemap_factory(inner: InnerParam) -> n2t.FancyOneToManyNoErrorNodeMap {
  fn(
    vxml: VXML,
    a: List(VXML),
    _: List(VXML),
    _: List(VXML),
    _: List(VXML),
  ) {
    nodemap(vxml, a, inner)
  }
}

fn transform_factory(inner: InnerParam) -> DesugarerTransform {
  nodemap_factory(inner)
  |> n2t.fancy_one_to_many_no_error_nodemap_2_desugarer_transform()
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(param)
}

type Param = List(#(String,        List(String)))
//                  ↖              ↖
//                  tag to         list of ancestor names
//                  be unwrapped   that will cause tag to unwrap
type InnerParam = Param

pub const name = "unwrap_if_descendant_of__batch"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// unwraps tags that are the descendant of one of a
/// stipulated list of tags
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
