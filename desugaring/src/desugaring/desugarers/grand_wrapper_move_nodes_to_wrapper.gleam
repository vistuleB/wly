import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
  type DesugaringWarning,
}
import desugaring/nodemaps_2_transform as n2t
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import on
import vxml.{type VXML, Attr, V}
import vxml/blame as bl

fn on_enter(
  vxml: VXML,
  state: State(a),
  inner: InnerParam(a),
) -> Result(
  #(Option(VXML), State(a), List(DesugaringWarning), core.TrafficLight),
  DesugaringError,
) {
  let #(a, vxmls) = state
  use #(a, result, warnings, light) <- on.ok(inner.1(a, vxml))
  let #(option_vxml, vxmls) = case result {
    Error(vxml) -> #(None, [vxml, ..vxmls])
    Ok(vxml) -> #(Some(vxml), vxmls)
  }
  Ok(#(option_vxml, #(a, vxmls), warnings, light))
}

fn on_exit(
  vxml: VXML,
  ancestors: List(VXML),
  original_state: State(a),
  latest_state: State(a),
  inner: InnerParam(a),
) -> Result(#(Option(VXML), State(a), List(DesugaringWarning)), DesugaringError) {
  let #(original_a, _) = original_state
  let #(latest_a, vxmls) = latest_state
  use #(latest_a, result, warnings) <- on.ok(inner.2(original_a, latest_a, vxml))
  let #(vxml, option_vxml, vxmls) = case result {
    Error(vxml) -> #(vxml, None, [vxml, ..vxmls])
    Ok(vxml) -> #(vxml, Some(vxml), vxmls)
  }
  let option_vxml = case ancestors {
    [] -> {
      let assert Some(_) = option_vxml
      let assert V(_, tag, _, _) = vxml
      let grand_wrapper = case tag {
        "GrandWrapper" -> vxml
        _ -> V(desugarer_blame(51), "GrandWrapper", [], [vxml])
      }
      let anointed_child =
        V(desugarer_blame(54), inner.4, [], vxmls |> list.reverse)
      let assert V(_, _, _, children) = grand_wrapper
      Some(V(..grand_wrapper, children: [anointed_child, ..children]))
    }
    _ -> option_vxml
  }
  Ok(#(option_vxml, #(latest_a, vxmls), warnings))
}

fn t_transform(
  vxml: VXML,
  state: State(a),
  inner: InnerParam(a),
) -> Result(#(Option(VXML), State(a), List(DesugaringWarning)), DesugaringError) {
  let #(a, vxmls) = state
  use #(a, result, warnings) <- on.ok(inner.3(a, vxml))
  let #(option_vxml, vxmls) = case result {
    Error(vxml) -> #(None, [vxml, ..vxmls])
    Ok(vxml) -> #(Some(vxml), vxmls)
  }
  Ok(#(option_vxml, #(a, vxmls), warnings))
}

fn nodemap_factory(
  inner: InnerParam(a),
) -> n2t.EarlyReturnFancyOneToOptionEnterExitStatefulWithWarningsNodemap(
  State(a),
) {
  n2t.EarlyReturnFancyOneToOptionEnterExitStatefulWithWarningsNodemap(
    on_enter: fn(vxml, _, _, _, _, state) { on_enter(vxml, state, inner) },
    on_exit: fn(vxml, ancestors, _, _, _, original_state, latest_state) {
      on_exit(vxml, ancestors, original_state, latest_state, inner)
    },
    on_text: fn(vxml, _, _, _, _, state) { t_transform(vxml, state, inner) },
  )
}

fn inner_param_to_transform(inner: InnerParam(a)) -> core.DesugarerTransform {
  n2t.early_return_fancy_one_to_option_enter_exit_stateful_with_warnings_nodemap_2_desugarer_transform(
    nodemap_factory(inner),
    #(inner.0, []),
  )
}

fn param_to_inner_param(
  param: Param(a),
) -> Result(InnerParam(a), DesugaringError) {
  Ok(param)
}

type State(a) =
  #(a, List(VXML))

type Param(
  a,
  // v_before -- returning Some(x) as second argument indicates desire to cut this node into the clipboard (second coordinate of State)
  // v_after
  // t
  // name of GrandWrapper child that will carry the nodes
) =
  #(
    a,
    fn(a, VXML) ->
      Result(
        #(a, Result(VXML, VXML), List(DesugaringWarning), core.TrafficLight),
        DesugaringError,
      ),
    fn(a, a, VXML) ->
      Result(#(a, Result(VXML, VXML), List(DesugaringWarning)), DesugaringError),
    fn(a, VXML) ->
      Result(#(a, Result(VXML, VXML), List(DesugaringWarning)), DesugaringError),
    String,
  )

type InnerParam(a) =
  Param(a)

pub const name = "grand_wrapper_move_nodes_to_wrapper"

fn desugarer_blame(line_no: Int) {
  bl.Des([], name, line_no)
}

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
/// Collects selected nodes during traversal and moves them
/// into a named child of a root `GrandWrapper`.
pub fn constructor(param: Param(a)) -> Desugarer {
  authoring.desugarer_with_stringified_param(
    name: name,
    param: param,
    stringified_param: "<functions>",
    prepare: param_to_inner_param,
    transform: inner_param_to_transform,
  )
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊

fn harvest_doomed_handles_from_grand_wrapper(vxml: VXML) -> List(String) {
  let assert V(_, "GrandWrapper", attrs, _) = vxml
  attrs
  |> list.filter(fn(attr) { attr.key == "source" })
  |> list.map(fn(attr) {
    let assert ">>" <> stuff = attr.val
    assert stuff == string.trim(stuff)
    stuff
  })
}

fn v_before_1(
  doomed_handles: List(String),
  vxml: VXML,
) -> Result(
  #(
    List(String),
    Result(VXML, VXML),
    List(DesugaringWarning),
    core.TrafficLight,
  ),
  DesugaringError,
) {
  let assert V(_, tag, attrs, _) = vxml
  let doomed_handles = case tag {
    "GrandWrapper" -> harvest_doomed_handles_from_grand_wrapper(vxml)
    _ -> doomed_handles
  }
  use #(attr, attrs) <- on.ok(core.attrs_extract_unique_key_or_none(
    attrs,
    "handle",
  ))
  use attr <- on.none_some(attr, fn() {
    Ok(#(doomed_handles, Ok(vxml), [], core.Continue))
  })
  let handle_name = string.trim(attr.val)
  use <- on.false_true(list.contains(doomed_handles, handle_name), fn() {
    Ok(#(doomed_handles, Ok(vxml), [], core.Continue))
  })
  // normalize the cut node, putting the (normalized) handle first:
  let vxml =
    V(..vxml, attrs: [
      Attr(desugarer_blame(198), attr.key, handle_name),
      ..attrs
    ])
  Ok(#(doomed_handles, Error(vxml), [], core.GoBack))
}

fn v_after_1(
  _: List(String),
  doomed_handles: List(String),
  vxml: VXML,
) -> Result(
  #(List(String), Result(VXML, VXML), List(DesugaringWarning)),
  DesugaringError,
) {
  Ok(#(doomed_handles, Ok(vxml), []))
}

fn t_1(
  doomed_handles: List(String),
  vxml: VXML,
) -> Result(
  #(List(String), Result(VXML, VXML), List(DesugaringWarning)),
  DesugaringError,
) {
  Ok(#(doomed_handles, Ok(vxml), []))
}

fn assertive_tests_data() -> List(core.AssertiveTestData(Param(List(String)))) {
  // a,
  // // v_before
  // fn(a, VXML) -> Result(#(a, List(Attr), List(DesugaringWarning), core.TrafficLight), DesugaringError),
  // // v_after
  // fn(a, a, VXML) -> Result(#(a, List(Attr), List(DesugaringWarning)), DesugaringError),
  // // t
  // fn(a, VXML) -> Result(#(a, List(Attr), List(DesugaringWarning)), DesugaringError),
  [
    // core.AssertiveTestData(
    //   param: #(
    //     [],
    //     v_before_1,
    //     v_after_1,
    //     t_1,
    //     "NodesBeingMoved",
    //   ),
    //   source: "
    //     <> root
    //       <> SomeGuy
    //   ",
    //   expected: "
    //     <> GrandWrapper
    //       <> NodesBeingMoved
    //       <> root
    //         <> SomeGuy
    //   ",
    // ),
    core.AssertiveTestData(
      param: #([], v_before_1, v_after_1, t_1, "NodesBeingMoved"),
      source: "
        <> GrandWrapper
          source=>>koolio
          source=>>koolio2
          <> root
            <> SomeGuy
            <> DoomedGuy
              handle=koolio
            <> OtherDoomedGuy
              handle=koolio2
            <> NotSoDoomed
              handle=koolio3
      ",
      expected: "
        <> GrandWrapper
          source=>>koolio
          source=>>koolio2
          <> NodesBeingMoved
            <> DoomedGuy
              handle=koolio
            <> OtherDoomedGuy
              handle=koolio2
          <> root
            <> SomeGuy
            <> NotSoDoomed
              handle=koolio3
      ",
    ),
  ]
}

pub fn assertive_tests() {
  core.assertive_test_collection_from_data(
    name,
    assertive_tests_data(),
    constructor,
  )
}
