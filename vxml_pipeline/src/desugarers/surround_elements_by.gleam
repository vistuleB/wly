import gleam/dict.{type Dict}
import gleam/list
import gleam/option
import gleam/string.{inspect as ins}
import infrastructure.{type Desugarer, Desugarer, type DesugarerTransform, type DesugaringError} as infra
import nodemaps_2_desugarer_transforms as n2t
import vxml.{type VXML, T, V}

fn nodemap(
  node: VXML,
  ancestors: List(VXML),
  inner: InnerParam,
) -> Result(List(VXML), DesugaringError) {
  case node {
    T(_, _) -> Ok([node])
    V(blame, tag, _, _) -> {
      case dict.get(inner, tag), list.length(ancestors) > 0 {
        Error(Nil), _ -> Ok([node])
        _, False -> Ok([node])
        Ok(#(above_tag, below_tag)), True -> {
          let some_none_above = case above_tag == "" {
            True -> option.None
            False ->
              option.Some(
                V(blame: blame, tag: above_tag, attributes: [], children: []),
              )
          }
          let some_none_below = case below_tag == "" {
            True -> option.None
            False ->
              option.Some(
                V(blame: blame, tag: below_tag, attributes: [], children: []),
              )
          }
          case some_none_above, some_none_below {
            option.None, option.None -> Ok([node])
            option.None, option.Some(below) -> Ok([node, below])
            option.Some(above), option.None -> Ok([above, node])
            option.Some(above), option.Some(below) -> Ok([above, node, below])
          }
        }
      }
    }
  }
}

fn nodemap_factory(inner: InnerParam) -> n2t.FancyOneToManyNodeMap {
  fn(node, ancestors, _, _, _) {
    nodemap(node, ancestors, inner)
  }
}

fn transform_factory(inner: InnerParam) -> DesugarerTransform {
  n2t.fancy_one_to_many_nodemap_2_desugarer_transform(nodemap_factory(inner))
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  let #(els, above, below) = param
  let inner_param = els
    |> list.map(fn(el) { #(el, #(above, below)) })
    |> dict.from_list
  Ok(inner_param)
}

type Param =
  #(List(String), String, String)
//  ↖            ↖       ↖
//  list of      name of name of
//  tag names    tag to  tag to
//  to surround  place   place
//               above   below

type InnerParam =
  Dict(String, #(String, String))

pub const name = "surround_elements_by"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// surrounds specified elements with above and below tags
/// the three tuple elements:
///    - list of tag names to surround
///    - name of tag to place above, or "" if none
///    - name of tag to place below, or "" if none
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
