import gleam/list
import gleam/option
import gleam/string.{inspect as ins}
import infrastructure.{type Desugarer, Desugarer, type DesugarerTransform, type DesugaringError} as infra
import nodemaps_2_desugarer_transforms as n2t
import vxml.{type VXML, T, V, TextLine }

fn line_wrap_in_list(
  already_wrapped: List(VXML),
  deficit: Int,
  last_was_text: Bool,
  remaining: List(VXML),
  inner: InnerParam,
) -> List(VXML) {
  case remaining {
    [] -> already_wrapped |> list.reverse
    [T(blame, lines), ..rest] -> {
      let deficit = case last_was_text {
        True -> 0
        False -> deficit
      }
      let #(lines, new_indent) =  infra.line_wrap_rearrangement(
        lines,
        deficit,
        inner.0,
      )
      line_wrap_in_list(
        [T(blame, lines), ..already_wrapped],
        new_indent,
        True,
        rest,
        inner,
      )
    }
    [V(_, _, _, _) as first, ..rest] -> {
      let deficit = case inner.1(first) {
        True -> infra.total_chars(first) + deficit
        False -> 0
      }
      let #(deficit, already_wrapped) = case deficit > inner.0 {
        True -> #(
          infra.total_chars(first),
          [first, T(first.blame, [TextLine(first.blame, "")]), ..already_wrapped]
        )
        False -> #(deficit, [first, ..already_wrapped])
      }
      line_wrap_in_list(
        already_wrapped,
        deficit,
        False,
        rest,
        inner,
      )
    }
  }
}

fn nodemap(
  vxml: VXML,
  inner: InnerParam,
) -> VXML {
  case vxml {
    T(_, _) -> vxml
    V(_, _, _, children) -> {
      let children = line_wrap_in_list(
        [],
        0,
        False,
        children,
        inner,
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
  |> n2t.one_to_one_no_error_nodemap_2_desugarer_transform_with_forbidden(outside)
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(param)
}

type Param = #(Int, fn(VXML) -> Bool)
type InnerParam = Param

pub const name = "line_rewrap_no1__outside"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// wraps lines after they go beyond a certain
/// length
///
/// accepts a function that determine which V-nodes
/// will be "folded" and have contents that should
/// be counted as a deficit toward the next T-node
pub fn constructor(param: Param, outside: List(String)) -> Desugarer {
  Desugarer(
    name: name,
    stringified_param: option.Some(ins(param)),
    stringified_outside: option.Some(ins(outside)),
    transform: case param_to_inner_param(param) {
      Error(error) -> fn(_) { Error(error) }
      Ok(inner) -> transform_factory(inner, outside)
    },
  )
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
fn assertive_tests_data() -> List(infra.AssertiveTestDataWithOutside(Param)) {
  []
}

pub fn assertive_tests() {
  infra.assertive_test_collection_from_data_with_outside(name, assertive_tests_data(), constructor)
}
