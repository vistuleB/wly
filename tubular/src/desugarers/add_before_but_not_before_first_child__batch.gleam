import gleam/dict.{type Dict}
import gleam/list
import gleam/option
import infrastructure.{type Desugarer, Desugarer, type DesugarerTransform, type DesugaringError} as infra
import nodemaps_2_desugarer_transforms as n2t
import vxml.{type VXML, V}
import blame as bl

fn add_in_list(
  vxmls: List(VXML),
  inner: InnerParam
) -> List(VXML) {
  case vxmls {
    [first, V(_, tag, _, _) as second, ..rest] -> {
      case dict.get(inner, tag) {
        Error(Nil) ->
          [first, ..add_in_list([second, ..rest], inner)]
        Ok(v) ->
          [first, v, ..add_in_list([second, ..rest], inner)]
      }
    }
    [first, second, ..rest] ->
      [first, ..add_in_list([second, ..rest], inner)]
    _ -> vxmls
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

fn nodemap_factory(inner: InnerParam) -> n2t.OneToOneNoErrorNodeMap {
  nodemap(_, inner)
}

fn transform_factory(inner: InnerParam) -> DesugarerTransform {
  nodemap_factory(inner)
  |> n2t.one_to_one_no_error_nodemap_2_desugarer_transform()
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  param
  |> list.map(
    fn(p) {
      #(
        p.0,
        infra.v_attrs_constructor(desugarer_blame(54), p.1, p.2),
      )
    }
  )
  |> infra.dict_from_list_with_desugaring_error
}

type Param = List(#(String,        String,          List(#(String, String))))
//                  ↖              ↖                ↖
//                  insert divs    tag name         attributes
//                  before tags    of new element
//                  of this name
//                  (except if tag is first child)
type InnerParam = Dict(String, VXML)

pub const name = "add_before_but_not_before_first_child__batch"
fn desugarer_blame(line_no: Int) {bl.Des([], name, line_no)}

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// adds new elements before specified tags but not 
/// if they are the first child
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
  []
}

pub fn assertive_tests() {
  infra.assertive_test_collection_from_data(name, assertive_tests_data(), constructor)
}
