import gleam/option
import gleam/list
import gleam/string.{inspect as ins}
import infrastructure.{type Desugarer, Desugarer, type DesugarerTransform, type DesugaringError} as infra
import nodemaps_2_desugarer_transforms as n2t
import vxml.{type VXML, V}
import blame as bl

fn add_in_list(
  children: List(VXML),
  inner: InnerParam,
) -> List(VXML) {
  case children {
    [
      V(_, first_tag, _, _) as first,
      V(_, second_tag, _, _) as second,
      ..rest
    ] -> case list.contains(inner.1, second_tag) && list.contains(inner.0, first_tag) {
      True -> {
        [
          first,
          inner.2,
          ..add_in_list([second, ..rest], inner),
        ]
      }
      False -> [first, ..add_in_list([second, ..rest], inner)]
    }
    [first, ..rest] -> [first, ..add_in_list(rest, inner)]
    _ -> children
  }
}

fn nodemap(
  node: VXML,
  inner: InnerParam,
) -> VXML {
  case node {
    V(_, _, _, children) ->
      V(..node, children: add_in_list(children, inner))
    _ -> node
  }
}

fn nodemap_factory(inner: InnerParam) -> n2t.OneToOneNoErrorNodemap {
  nodemap(_, inner)
}

fn transform_factory(inner: InnerParam) -> DesugarerTransform {
  nodemap_factory(inner)
  |> n2t.one_to_one_no_error_nodemap_2_desugarer_transform()
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  #(param.0, param.1, V(desugarer_blame(53), param.2, [], []))
  |> Ok
}

type Param = #(List(String),   List(String), String)
//                  ↖              ↗         ↖
//                  insert divs              tag name for
//                  between adjacent         new element
//                  siblings of these
//                  two names
type InnerParam = #(List(String), List(String), VXML)

pub const name = "add_between_all_pairs_2"
fn desugarer_blame(line_no: Int) { bl.Des([], name, line_no) }

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// adds new element between any two V-nodes where
/// the tag of the first node comes from the first
/// list and the tag of the second node comes from
/// the second list; the '_2' means that, for
/// efficiency purposes, this desugarer should be
/// used when the 2nd list is the smaller one
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
      param: #(["a", "b", "c"], ["D", "E"], "NEWGUY"),
      source: "
        <> root
          <> D
          <> a
          <> b
          <> D
          <> E
          <> a
          <> c
          <> c
          <> D
      ",
      expected: "
        <> root
          <> D
          <> a
          <> b
          <> NEWGUY
          <> D
          <> E
          <> a
          <> c
          <> c
          <> NEWGUY
          <> D
      "
    )
  ]
}

pub fn assertive_tests() {
  infra.assertive_test_collection_from_data(name, assertive_tests_data(), constructor)
}
