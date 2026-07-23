import gleam/dict.{type Dict}
import gleam/list
import gleam/option.{type Option, Some}
import gleam/string.{inspect as ins}
import infrastructure.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
  type DesugaringWarning, Desugarer, DesugaringError, DesugaringWarning,
} as infra
import nodemaps_2_desugarer_transforms as n2t
import on
import vxml.{type Attr, type VXML, V}

fn collect_unused_ids(
  attrs: List(Attr),
) -> Result(Dict(String, List(String)), DesugaringError) {
  list.try_fold(attrs, dict.new(), fn(acc, attr) {
    case attr.key == "handle" {
      False -> Ok(acc)
      True ->
        case attr.val |> string.split("|") {
          [_, _, _, _, _, "used"] -> Ok(acc)
          [name, _, _, id, _, ""] ->
            Ok(
              dict.upsert(acc, id, fn(existing) {
                [name, ..option.unwrap(existing, [])]
              }),
            )
          _ ->
            Error(DesugaringError(
              attr.blame,
              "GrandWrapper handle entry has no 'used' column (run "
                <> "handles_substitute first); found: “"
                <> attr.val
                <> "”",
            ))
        }
    }
  })
}

fn traffic_light(remaining: Dict(String, List(String))) -> infra.TrafficLight {
  case dict.is_empty(remaining) {
    True -> infra.GoBack
    False -> infra.Continue
  }
}

fn warnings_for(
  names: List(String),
  vxml: VXML,
  inner: InnerParam,
) -> List(DesugaringWarning) {
  let assert V(blame, tag, _, _) = vxml
  case list.contains(inner, tag) {
    False -> []
    True ->
      names
      |> list.map(fn(name) {
        DesugaringWarning(
          blame,
          "handle '"
            <> name
            <> "' is defined on a '"
            <> tag
            <> "' element but is never used",
        )
      })
  }
}

fn v_before(
  vxml: VXML,
  state: State,
  inner: InnerParam,
) -> Result(
  #(VXML, State, List(DesugaringWarning), infra.TrafficLight),
  DesugaringError,
) {
  let assert V(_, tag, attrs, _) = vxml

  case tag {
    "GrandWrapper" -> {
      use remaining <- on.ok(collect_unused_ids(attrs))
      let state = State(..state, remaining: remaining)
      Ok(#(vxml, state, [], traffic_light(remaining)))
    }

    _ -> {
      let state = case our_id(vxml) {
        Some(id) ->
          case dict.get(state.remaining, id) {
            Ok(names) ->
              State(
                remaining: dict.delete(state.remaining, id),
                warnings: infra.pour(
                  warnings_for(names |> list.reverse, vxml, inner),
                  state.warnings,
                ),
              )
            Error(_) -> state
          }
        _ -> state
      }
      Ok(#(vxml, state, [], traffic_light(state.remaining)))
    }
  }
}

fn our_id(vxml: VXML) -> Option(String) {
  infra.v_first_attr_with_key(vxml, "id")
  |> option.map(fn(attr) { attr.val })
}

fn v_after(
  vxml: VXML,
  _original_state: State,
  latest_state: State,
) -> Result(#(VXML, State, List(DesugaringWarning)), DesugaringError) {
  let assert V(_, tag, _, _) = vxml
  case tag {
    // the GrandWrapper is the root: this is the one and only place where
    // the accumulated warnings are handed over to the pipeline
    "GrandWrapper" ->
      Ok(#(vxml, latest_state, latest_state.warnings |> list.reverse))
    _ -> Ok(#(vxml, latest_state, []))
  }
}

fn nodemap_factory(
  inner: InnerParam,
) -> n2t.EarlyReturnOneToOneBeforeAndAfterStatefulNodemapWithWarnings(State) {
  n2t.EarlyReturnOneToOneBeforeAndAfterStatefulNodemapWithWarnings(
    v_before_transforming_children: fn(vxml, state) {
      v_before(vxml, state, inner)
    },
    v_after_transforming_children: v_after,
    t_nodemap: fn(vxml, state) { Ok(#(vxml, state, [])) },
  )
}

fn transform_factory(inner: InnerParam) -> DesugarerTransform {
  n2t.early_return_one_to_one_before_and_after_stateful_nodemap_with_warnings_2_desugarer_transform(
    nodemap_factory(inner),
    State(dict.new(), []),
  )
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(param)
}

type State {
  State(
    // id -> names of the handles that point to it, for handles that the
    // GrandWrapper dictionary marks as unused; an entry is dropped as
    // soon as the node bearing that id is reached
    remaining: Dict(String, List(String)),
    // the early-return walker drops the warnings returned by
    // v_before_transforming_children whenever it is told to GoBack, so we
    // accumulate them in the state and emit them all at the root instead
    warnings: List(DesugaringWarning),
  )
}

type Param =
  List(String)

// tags for which an unused handle is worth warning about
type InnerParam =
  Param

pub const name = "handles_warn_unused"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// Expects a document whose root is a 'GrandWrapper'
/// carrying a handle dictionary in the 6-column form
/// left behind by handles_substitute:
///
/// handle=<name>|<page>|<value>|<id>|<path>|used
/// handle=<name>|<page>|<value>|<id>|<path>|
///
/// Emits one DesugaringWarning per handle whose
/// 'used' column is empty and whose id points to a
/// node whose tag is listed in the param, blamed on
/// that node. (Passing ["MathBlock"] therefore
/// reports unused equation handles.)
///
/// Handles on nodes of any other tag are silently
/// ignored, as are ids that no node carries.
///
/// Leaves the tree unchanged; must run before the
/// GrandWrapper is unwrapped.
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
    // Test 1: unused handle on a MathBlock -> tree unchanged (the
    // warning itself is not observable through assertive tests)
    infra.AssertiveTestData(
      param: ["MathBlock"],
      source: "
        <> GrandWrapper
          handle=eq:unused||(1.1)|_1_h.a.i_|./ch1.html|
          <> root
            <> Chapter
              path=./ch1.html
              <> MathBlock
                id=_1_h.a.i_
                <>
                  'x = y'
      ",
      expected: "
        <> GrandWrapper
          handle=eq:unused||(1.1)|_1_h.a.i_|./ch1.html|
          <> root
            <> Chapter
              path=./ch1.html
              <> MathBlock
                id=_1_h.a.i_
                <>
                  'x = y'
      ",
    ),

    // Test 2: used handle on a MathBlock -> tree unchanged
    infra.AssertiveTestData(
      param: ["MathBlock"],
      source: "
        <> GrandWrapper
          handle=eq:used||(1.1)|_1_h.a.i_|./ch1.html|used
          <> root
            <> Chapter
              path=./ch1.html
              <> MathBlock
                id=_1_h.a.i_
                <>
                  'x = y'
      ",
      expected: "
        <> GrandWrapper
          handle=eq:used||(1.1)|_1_h.a.i_|./ch1.html|used
          <> root
            <> Chapter
              path=./ch1.html
              <> MathBlock
                id=_1_h.a.i_
                <>
                  'x = y'
      ",
    ),

    // Test 3: unused handle on a non-listed tag -> tree unchanged
    infra.AssertiveTestData(
      param: ["MathBlock"],
      source: "
        <> GrandWrapper
          handle=sec:intro||1.1|_1_h.a.i_|./ch1.html|
          <> root
            <> Chapter
              path=./ch1.html
              <> Section
                id=_1_h.a.i_
                <>
                  'Introduction'
      ",
      expected: "
        <> GrandWrapper
          handle=sec:intro||1.1|_1_h.a.i_|./ch1.html|
          <> root
            <> Chapter
              path=./ch1.html
              <> Section
                id=_1_h.a.i_
                <>
                  'Introduction'
      ",
    ),
  ]
}

pub fn assertive_tests() {
  infra.assertive_test_collection_from_data(
    name,
    assertive_tests_data(),
    constructor,
  )
}
