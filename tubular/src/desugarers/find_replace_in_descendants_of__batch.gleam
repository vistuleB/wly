import gleam/list
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
) -> VXML {
  case vxml {
    V(_, _, _, _) -> vxml
    T(_, _) -> {
      list.fold(inner, vxml, fn(v, tuple) -> VXML {
        let #(ancestor, list_pairs) = tuple
        case list.any(ancestors, fn(a) { infra.v_get_tag(a) == ancestor }) {
          False -> v
          True -> infra.t_find_replace__batch(vxml, list_pairs)
        }
      })
    }
  }
}

fn nodemap_factory(inner: InnerParam) -> n2t.FancyOneToOneNoErrorNodeMap {
  fn(vxml, ancestors, s1, s2, s3) {
    nodemap(vxml, ancestors, s1, s2, s3, inner)
  }
}

fn transform_factory(inner: InnerParam) -> DesugarerTransform {
  n2t.fancy_one_to_one_no_error_nodemap_2_desugarer_transform(nodemap_factory(inner))
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(param)
}

type Param = List(#(String,   List(#(String, String))))
//                  ↖         ↖
//                  ancestor  from/to pairs
type InnerParam = Param

pub const name = "find_replace_in_descendants_of__batch"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// find and replace strings in text nodes that are
/// descendants of specified ancestor tags
pub fn constructor(param: Param) -> Desugarer {
  Desugarer(
    name: name,
    stringified_param: option.Some(param |> infra.list_param_stringifier),
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
    infra.AssertiveTestData(
      param: [#("ancestor", [#("_FROM_", "_TO_")])],
      source:   "
                <> root
                  <> B
                    <>
                      \"hello _FROM_\"
                      \"_FROM__FROM_\"
                  <> ancestor
                    <> B
                      <>
                        \"hello _FROM_\"
                        \"_FROM__FROM_\"
                ",
      expected: "
                <> root
                  <> B
                    <>
                      \"hello _FROM_\"
                      \"_FROM__FROM_\"
                  <> ancestor
                    <> B
                      <>
                        \"hello _TO_\"
                        \"_TO__TO_\"
                ",
    )
  ]
}

pub fn assertive_tests() {
  infra.assertive_test_collection_from_data(name, assertive_tests_data(), constructor)
}
