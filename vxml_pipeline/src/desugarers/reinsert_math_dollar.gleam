import gleam/dict
import gleam/list
import gleam/option
import gleam/string.{inspect as ins}
import infrastructure.{type Desugarer, Desugarer, type DesugarerTransform, type DesugaringError} as infra
import nodemaps_2_desugarer_transforms as n2t
import vxml.{type VXML, TextLine, T, V}

type Where {
  First
  Last
  Both
}

fn insert_dollar(node: VXML, dollar: String, where: Where) -> List(VXML) {
  case node {
    T(blame, contents) -> {
      case where {
        First -> [T(blame, [TextLine(blame, dollar), ..contents])]
        Last -> [
          T(blame, list.append(contents, [TextLine(blame, dollar)])),
        ]
        Both -> [
          T(
            blame,
            list.flatten([
              [TextLine(blame, dollar)],
              contents,
              [TextLine(blame, dollar)],
            ]),
          ),
        ]
      }
    }
    V(blame, _, _, _) -> {
      case where {
        First -> [T(blame, [TextLine(blame, dollar)]), node]
        Last -> [node, T(blame, [TextLine(blame, dollar)])]
        Both -> [
          T(blame, [TextLine(blame, dollar)]),
          node,
          T(blame, [TextLine(blame, dollar)]),
        ]
      }
    }
  }
}

fn update_children(nodes: List(VXML), dollar: String) -> List(VXML) {
  let assert [first, ..rest] = nodes
  case list.last(rest) {
    Ok(_) -> {
      panic as { "more than 1 child in node:" <> ins(nodes) }
      // let assert [_, ..in_between_reversed] = rest |> list.reverse
      // list.flatten([
      //   insert_dollar(first, dollar, First),
      //   in_between_reversed |> list.reverse(),
      //   insert_dollar(last, dollar, Last),
      // ])
    }
    Error(_) -> {
      insert_dollar(first, dollar, Both)
    }
  }
}

fn nodemap(
  vxml: VXML,
) -> Result(VXML, DesugaringError) {
  let math_map = dict.from_list([#("Math", "$"), #("MathBlock", "$$")])

  case vxml {
    V(blame, tag, atts, children) -> {
      case dict.get(math_map, tag) {
        Ok(delimiter) -> {
          Ok(V(blame, tag, atts, update_children(children, delimiter)))
        }
        Error(_) -> Ok(vxml)
      }
    }
    _ -> Ok(vxml)
  }
}

fn nodemap_factory(_: InnerParam) -> n2t.OneToOneNodeMap {
  nodemap
}

fn transform_factory(inner: InnerParam) -> DesugarerTransform {
  n2t.one_to_one_nodemap_2_desugarer_transform(nodemap_factory(inner))
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(param)
}

type Param = Nil
type InnerParam = Nil

pub const name = "reinsert_math_dollar"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// reinserts dollar delimiters into Math and
/// MathBlock elements
pub fn constructor(param: Param) -> Desugarer {
  Desugarer(
    name: name,
    stringified_param: option.None,
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
