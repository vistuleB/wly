import gleam/list
import gleam/option
import infrastructure.{ type Desugarer, Desugarer, type DesugarerTransform, type DesugaringError } as infra
import nodemaps_2_desugarer_transforms as n2t
import vxml.{type VXML, V, T, type Line, Line}

fn remove_first_line_while_empty(
  lines: List(Line),
) -> List(Line) {
  case lines {
    [Line(_, ""), ..rest] -> remove_first_line_while_empty(rest)
    _ -> lines
  }
}

fn remove_last_line_while_empty(
  lines: List(Line),
) -> List(Line) {
  lines |> list.reverse |> remove_first_line_while_empty |> list.reverse
}

fn delete_in_list(
  prev_in_list: Bool,
  remaining: List(VXML),
  inner: InnerParam,
) -> List(VXML) {
  case remaining {
    [T(blame, lines), V(_, tag, _, _) as second, ..rest] -> {
      let lines = case prev_in_list {
        True -> remove_first_line_while_empty(lines)
        False -> lines
      }
      let lines = case list.contains(inner, tag) {
        False -> lines
        True -> remove_last_line_while_empty(lines)
      }
      case lines {
        [] -> delete_in_list(False, [second, ..rest], inner)
        _ -> [T(blame, lines), ..delete_in_list(False, [second, ..rest], inner)]
      }
    }
    [T(blame, lines), T(..) as second, ..rest] -> {
      let lines = case prev_in_list {
        True -> remove_first_line_while_empty(lines)
        False -> lines
      }
      case lines {
        [] -> delete_in_list(False, [second, ..rest], inner)
        _ -> [T(blame, lines), ..delete_in_list(False, [second, ..rest], inner)]
      }
    }
    [T(blame, lines)] -> {
      let lines = case prev_in_list {
        True -> remove_first_line_while_empty(lines)
        False -> lines
      }
      |> remove_last_line_while_empty
      case lines {
        [] -> []
        _ -> [T(blame, lines)]
      }
    }
    [V(_, tag, _, _) as first, ..rest] -> {
      let rest = delete_in_list(
        list.contains(inner, tag),
        rest,
        inner,
      )
      [first, ..rest]
    }
    [] -> []
  }
}

fn nodemap(
  node: VXML,
  inner: InnerParam,
) -> VXML {
  case node {
    T(..) -> node
    V(_, _, _, children) -> {
      let children = delete_in_list(True, children, inner)
      V(..node, children: children)
    }
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
  Ok(param)
}

type Param = List(String)
type InnerParam = Param

pub const name = "delete_empty_lines_before_after"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
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
