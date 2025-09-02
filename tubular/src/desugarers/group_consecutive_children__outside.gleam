import gleam/list
import gleam/option
import gleam/string.{inspect as ins}
import infrastructure.{type Desugarer, Desugarer, type DesugarerTransform, type DesugaringError, DesugaringError} as infra
import nodemaps_2_desugarer_transforms as n2t
import vxml.{type VXML, T, V}
import blame.{type Blame} as bl

fn is_forbidden(elem: VXML, forbidden: List(String)) {
  case elem {
    T(_, _) -> False
    V(_, tag, _, _) -> list.contains(forbidden, tag)
  }
}

fn nodemap(
  vxml: VXML,
  inner: InnerParam,
) -> VXML {
  case vxml {
    T(_, _) -> vxml
    V(_, _, _, children) -> {
      let children =
        children
        |> infra.either_or_misceginator(is_forbidden(_, inner.1))
        |> infra.regroup_ors_no_empty_lists
        |> infra.map_either_ors(
          fn(x){x},
          fn(consecutive_siblings) {
            V(
              inner.2, // Blame
              inner.0, // wrapper tag
              [],
              consecutive_siblings,
            )
          }
        )
      V(..vxml, children: children)
    }
  }
}

fn nodemap_factory(inner: InnerParam) -> n2t.OneToOneNoErrorNodeMap {
  nodemap(_, inner)
}

fn transform_factory(inner: InnerParam, outside: List(String)) -> DesugarerTransform {
  nodemap_factory(inner)
  |> n2t.one_to_one_no_error_nodemap_2_desugarer_transform_with_forbidden_self_first(outside)
}

fn param_to_inner_param(param: Param, outside: List(String)) -> Result(InnerParam, DesugaringError) {
  case list.contains(outside, param.0) {
    True -> Ok(#(param.0, param.1, desugarer_blame(54)))
    False -> Error(DesugaringError(
      bl.no_blame,
      "the wrapper must be included either in the list of things not to be contained in in order to avoid infinite recursion")
    )
  }
}

type Param = #(String,   List(String))
//             ↖         ↖
//             wrapper   do not
//                       wrap
//                       these
type InnerParam = #(String, List(String), Blame)

pub const name = "group_consecutive_children__outside"
fn desugarer_blame(line_no: Int) {bl.Des([], name, line_no)}

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// when called with params
///
///   - wrapper_tag: String
///   - dont_wrap_these: List(String)
///   - dont_enter_here: List(String)
///
/// will wrap all groups of consecutive children
/// where the group does not contain a tag from
/// dont_wrap_these with a wrapper_tag node, while
/// not processing subtrees rooted at nodes of tag
/// dont_enter_here untouched; see tests
pub fn constructor(param: Param, outside: List(String)) -> Desugarer {
  Desugarer(
    name: name,
    stringified_param: option.Some(ins(param)),
    stringified_outside: option.Some(ins(outside)),
    transform: case param_to_inner_param(param, outside) {
      Error(error) -> fn(_) { Error(error) }
      Ok(inner) -> transform_factory(inner, outside)
    },
  )
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
fn assertive_tests_data() -> List(infra.AssertiveTestDataWithOutside(Param)) {
  [
    infra.AssertiveTestDataWithOutside(
      param: #("wrapper", ["A", "B"]),
      outside: ["B", "C", "wrapper"],
      source:   "
                <> root
                  <> x
                  <> y
                  <> A
                  <> B
                    <> x
                    <> y
                  <> x
                  <> C
                    <> x
                    <> y
                ",
      expected: "
                <> root
                  <> wrapper
                    <> x
                    <> y
                  <> A
                  <> B
                    <> x
                    <> y
                  <> wrapper
                    <> x
                    <> C
                      <> x
                      <> y
                "
    )
  ]
}

pub fn assertive_tests() {
  infra.assertive_test_collection_from_data_with_outside(name, assertive_tests_data(), constructor)
}
