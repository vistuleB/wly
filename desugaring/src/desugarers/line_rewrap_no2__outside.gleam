import gleam/list
import gleam/int
import gleam/option
import gleam/string.{inspect as ins}
import infrastructure.{type Desugarer, Desugarer, type DesugarerTransform, type DesugaringError} as infra
import nodemaps_2_desugarer_transforms as n2t
import vxml.{ type VXML, T, V, Line }
import blame.{ Des }

const const_blame = Des([], name, 9)
const one_empty_line = T(const_blame, [Line(const_blame, "")])

fn line_wrap_in_list(
  already_wrapped: List(VXML),
  deficit: Int,
  last_was_text: Bool,
  remaining: List(VXML),
  line_length: Int,
  incorporating_condition: fn(VXML) -> Bool,
) -> List(VXML) {
  case remaining {
    [] -> already_wrapped |> list.reverse
    [T(blame, lines), ..rest] -> {
      let deficit = case last_was_text {
        True -> 0
        False -> deficit
      }
      let #(lines, new_indent) = infra.line_wrap_rearrangement(
        lines,
        deficit,
        line_length,
      )
      line_wrap_in_list(
        [T(blame, lines), ..already_wrapped],
        new_indent,
        True,
        rest,
        line_length,
        incorporating_condition,
      )
    }
    [V(_, _, _, _) as first, ..rest] -> {
      let deficit = case incorporating_condition(first) {
        True -> infra.total_chars(first) + deficit
        False -> 0
      }
      let #(deficit, already_wrapped) = case deficit > line_length {
        True -> #(
          // this can only occur if the V-node is incorporated
          // (else deficit == 0), and in which case we want that
          // V-node to go on its own new line, which is why we
          // insert the empty text line as buffer (it will suck
          // up the last_to_first concatenation coming from the
          // V-node):
          infra.total_chars(first),
          [first, one_empty_line, ..already_wrapped]
        )
        False -> #(deficit, [first, ..already_wrapped])
      }
      line_wrap_in_list(
        already_wrapped,
        deficit,
        False,
        rest,
        line_length,
        incorporating_condition,
      )
    }
  }
}

fn v_before(
  vxml: VXML,
  state: State,
  inner: InnerParam,
) -> #(VXML, State) {
  let assert V(_, tag, _, _) = vxml
  case list.contains(inner.0, tag) {
    True -> #(vxml, 0)
    False -> #(vxml, state + inner.3)
  }
}

fn v_after(
  vxml: VXML,
  original_state: State,
  state: State,
  inner: InnerParam,
) -> #(VXML, State) {
  let assert V(_, _, _, children) = vxml
  let children = line_wrap_in_list(
    [],
    0,
    False,
    children,
    int.max(inner.1 - state - 1, inner.2),
    inner.4,
  )
  #(V(..vxml, children: children), original_state)
}

fn nodemap_factory(
  inner: InnerParam
) -> n2t.OneToOneBeforeAndAfterNoErrorStatefulNodeMap(State) {
  n2t.OneToOneBeforeAndAfterNoErrorStatefulNodeMap(
    v_before_transforming_children: fn(v: VXML, s: State) {
      v_before(v, s, inner)
    },
    v_after_transforming_children: fn(v: VXML, o: State, s: State) {
      v_after(v, o, s, inner)
    },
    t_nodemap: fn(v, state){#(v, state)},
  )
}

fn transform_factory(inner: InnerParam, outside: List(String)) -> DesugarerTransform {
  nodemap_factory(inner)
  |> n2t.one_to_one_before_and_after_no_error_stateful_nodemap_2_desugarer_transform_with_forbidden(0, outside)
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(param)
}

type State = Int

type Param = #(List(String),   Int,       Int,       Int,                       fn(VXML) -> Bool)
//             ↖               ↖          ↖          ↖                          ↖
//             tags that       max line   min line   amt to reduce              condition that tells whether
//             cause reset     length     length     max line length            a node will be folded into text
//             of indent to 0                        at each level of nesting   in future (of pipeline) (and therefore to leave room for contents on that line)
type InnerParam = Param

pub const name = "line_rewrap_no2__outside"

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
