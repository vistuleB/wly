import gleam/option
import gleam/string.{inspect as ins}
import infrastructure.{type Desugarer, Desugarer, type DesugarerTransform, type DesugaringError} as infra
import nodemaps_2_desugarer_transforms as n2t
import vxml.{type VXML, V}

fn delete_in_list(
  children: List(VXML),
  inner: InnerParam,
) -> List(VXML) {
  case children {
    [V(_, tag, _, _), ..rest] if tag == inner -> delete_in_list(rest, inner)
    _ -> children
  }
}

fn nodemap(
  vxml: VXML,
  inner: InnerParam,
) -> VXML {
  case vxml {
    V(_, _, _, [V(_, tag, _, _), ..rest]) if tag == inner -> V(..vxml, children: delete_in_list(rest, inner))
    _ -> vxml
  }
}

fn nodemap_factory(inner: InnerParam) -> n2t.OneToOneNoErrorNodemap {
  nodemap(_, inner)
}

fn transform_factory(inner: InnerParam) -> DesugarerTransform {
  nodemap_factory(inner)
  |> n2t.one_to_one_no_error_nodemap_2_desugarer_transform
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(param)
}

type Param = String
type InnerParam = Param

pub const name = "delete_first_child_occurrences_of_and_recurse"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// removes all V-nodes of a certain tag when they
/// occur as the first child of a node, and recurses
/// (that guarantees the final tree has no such nodes as
/// first children)
/// 
/// is not efficient if the thing to be deleted has
/// children; if you want to do that plz write another
/// depth-first-search desugarer
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
    infra.AssertiveTestData(
      param: "ToBeDeleted",
      source:   "
                <> Root
                  <> ToBeDeleted
                  <> ToBeDeleted
                  <> a
                  <> ToBeDeleted
                ",
      expected: "
                <> Root
                  <> a
                  <> ToBeDeleted
                ",
    ),
  ]
}

pub fn assertive_tests() {
  infra.assertive_test_collection_from_data(name, assertive_tests_data(), constructor)
}