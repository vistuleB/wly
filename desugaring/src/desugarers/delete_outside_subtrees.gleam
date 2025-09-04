import gleam/list
import gleam/string.{inspect as ins}
import gleam/option
import infrastructure.{type Desugarer, Desugarer, type DesugarerTransform, type DesugaringError} as infra
import nodemaps_2_desugarer_transforms as n2t
import vxml.{type VXML, T, V}

fn nodemap(
  vxml: VXML,
  ancestors: List(VXML),
  _: List(VXML),
  _: List(VXML),
  _: List(VXML),
  inner: InnerParam,
) -> List(VXML) {
  case vxml {
    T(_, _) ->
      case list.any(ancestors, inner) {
        True -> [vxml]
        False -> []
      }
    V(_, _, _, children) -> {
      case
        !list.is_empty(children) || list.any(ancestors, inner) || inner(vxml)
      {
        True -> [vxml]
        False -> []
      }
    }
  }
}

fn nodemap_factory(inner: InnerParam) -> n2t.FancyOneToManyNoErrorNodeMap {
  fn(vxml, a, s1, s2, s3) { nodemap(vxml, a, s1, s2, s3, inner) }
}

fn transform_factory(inner: InnerParam) -> DesugarerTransform {
  nodemap_factory(inner)
  |> n2t.fancy_one_to_many_no_error_nodemap_2_desugarer_transform()
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(param)
}

type Param = fn(VXML) -> Bool
//             ↖
//             a node is saved
//             iff one of its
//             ancestors fulfills
//             this condition
type InnerParam = Param

pub const name = "delete_outside_subtrees"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// removes nodes that are outside subtrees matching
/// the predicate function
pub fn constructor(param: Param) -> Desugarer {
  Desugarer(
    name: name,
    stringified_param: option.Some(ins(param)),
    stringified_outside: option.None,
    transform: case param_to_inner_param(param) {
      Ok(inner) -> transform_factory(inner)
      Error(error) -> fn(_) { Error(error) }
    }
  )
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
fn assertive_tests_data() -> List(infra.AssertiveTestData(Param)) {
  [
    infra.AssertiveTestData(
      param: infra.is_v_and_tag_equals(_, "keep_this"),
      source:   "
                <> R
                  <>
                    \"hello world\"
                  <> blabla
                  <> keep_this
                    <>
                      \"hello world\"
                ",
      expected: "
                <> R
                  <> keep_this
                    <>
                      \"hello world\"
                ",
    ),
  ]
}

pub fn assertive_tests() {
  infra.assertive_test_collection_from_data(name, assertive_tests_data(), constructor)
}
