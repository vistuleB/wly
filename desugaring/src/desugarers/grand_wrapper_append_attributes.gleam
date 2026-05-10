import gleam/result
import gleam/list
import gleam/string
import gleam/option
import infrastructure.{
  type Desugarer,
  type DesugarerTransform,
  type DesugaringError,
  type DesugaringWarning,
  DesugaringWarning,
  Desugarer,
} as infra
import nodemaps_2_desugarer_transforms as n2t
import vxml.{type Attr, type VXML, V, T, Attr, type Line}
import blame as bl
import on

fn v_before_transforming_children(
  vxml: VXML,
  state: State(a),
  inner: InnerParam(a),
) -> Result(#(VXML, State(a), List(DesugaringWarning), infra.TrafficLight), DesugaringError) {
  let #(a, attrs) = state
  use #(a, local_attrs, warnings, light) <- on.ok(inner.1(a, vxml))
  let attrs = list.append(attrs, local_attrs)
  Ok(#(vxml, #(a, attrs), warnings, light))
}

fn v_after_transforming_children(
  vxml: VXML,
  ancestors: List(VXML),
  original_state: State(a),
  latest_state: State(a),
  inner: InnerParam(a),
) -> Result(#(VXML, State(a), List(DesugaringWarning)), DesugaringError) {
  let #(latest_a, latest_attrs) = latest_state
  let #(original_a, _) = original_state
  use #(latest_a, local_attrs, warnings) <- on.ok(inner.2(original_a, latest_a, vxml))
  let latest_attrs = list.append(latest_attrs, local_attrs)
  let vxml = case ancestors {
    [] -> {
      let assert V(_, tag, attrs, _) = vxml
      case tag {
        "GrandWrapper" -> V(..vxml, attrs: list.append(attrs, latest_attrs))
        _ -> V(
          desugarer_blame(46),
          "GrandWrapper",
          latest_attrs,
          [vxml],
        )
      }
    }
    _ -> vxml
  }
  Ok(#(vxml, #(latest_a, latest_attrs), warnings))
}

fn t_transform(
  vxml: VXML,
  state: State(a),
  inner: InnerParam(a),
) -> Result(#(VXML, State(a), List(DesugaringWarning)), DesugaringError) {
  let #(a, attrs) = state
  use #(a, local_attrs, warnings) <- on.ok(inner.3(a, vxml))
  let attrs = list.append(attrs, local_attrs)
  Ok(#(vxml, #(a, attrs), warnings))
}

fn nodemap_factory(inner: InnerParam(a)) -> n2t.EarlyReturnFancyOneToOneBeforeAndAfterStatefulNodemapWithWarnings(State(a)) {
   n2t.EarlyReturnFancyOneToOneBeforeAndAfterStatefulNodemapWithWarnings(
    v_before_transforming_children: fn(vxml, _, _, _, _, state) {
      v_before_transforming_children(vxml, state, inner)
    },
    v_after_transforming_children: fn(vxml, ancestors, _, _, _, original_state, latest_state) {
      v_after_transforming_children(vxml, ancestors, original_state, latest_state, inner)
    },
    t_nodemap: fn(vxml, _, _, _, _, state) {
      t_transform(vxml, state, inner)
    },
  )
}

fn transform_factory(inner: InnerParam(a)) -> infra.DesugarerTransform {
  n2t.early_return_fancy_one_to_one_before_and_after_stateful_nodemap_with_warnings_2_desugarer_transform(
    nodemap_factory(inner),
    #(inner.0, []),
  )
}

fn param_to_inner_param(param: Param(a)) -> Result(InnerParam(a), DesugaringError) {
  Ok(param)
}

type State(a) = #(a, List(Attr))

type Param(a) = #(
  a,
  // v_before
  fn(a, VXML) -> Result(#(a, List(Attr), List(DesugaringWarning), infra.TrafficLight), DesugaringError),
  // v_after
  fn(a, a, VXML) -> Result(#(a, List(Attr), List(DesugaringWarning)), DesugaringError),
  // t
  fn(a, VXML) -> Result(#(a, List(Attr), List(DesugaringWarning)), DesugaringError),
)

type InnerParam(a) = Param(a)

pub const name = "grand_wrapper_append_attributes"
fn desugarer_blame(line_no: Int) { bl.Des([], name, line_no) }

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
pub fn constructor(param: Param(a)) -> Desugarer {
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

fn tag_past_root(tag: String) -> infra.TrafficLight {
  case tag {
    "GrandWrapper" | "root" | "Book" -> infra.Continue
    _ -> infra.GoBack
  }
}

fn v_before_1(_: Nil, vxml: VXML) -> Result(#(Nil, List(Attr), List(DesugaringWarning), infra.TrafficLight), DesugaringError){
  let assert V(_, tag, attrs, _) = vxml
  use <- on.false_true(
    tag == "In",
    fn() { Ok(#(Nil, [], [], tag_past_root(tag))) }
  )
  use <- on.false_true(
    infra.attrs_have_key_val(attrs, "chapter", ">>exercise-graveyard"),
    fn() { Ok(#(Nil, [], [], infra.GoBack)) }
  )
  Ok(#(
    Nil,
    [Attr(desugarer_blame(150), "hey", "hello")],
    [],
    infra.GoBack
  ))
}

fn v_after_1(_: Nil, _: Nil, _vxml: VXML) -> Result(#(Nil, List(Attr), List(DesugaringWarning)), DesugaringError) {
  Ok(#(Nil, [], []))
}

fn t_1(_: Nil, _vxml: VXML) -> Result(#(Nil, List(Attr), List(DesugaringWarning)), DesugaringError) {
  Ok(#(Nil, [], []))
}

fn harvest_handle_attrs_from_line(line: Line) -> Result(Attr, DesugaringWarning) {
  case line.content {
    ">>" <> stuff -> {
      let stuff = string.trim(stuff)
      case string.contains(stuff, " ") || string.contains(stuff, ">") {
        True -> Error(DesugaringWarning(line.blame, "handle contains space or '>': " <> stuff))
        False -> Ok(Attr(desugarer_blame(170), "source", ">>" <> stuff))
      }
    }
    _ -> Error(DesugaringWarning(line.blame, "'>>' not found in text node"))
  }
}

fn harvest_handle_attrs_from_lines(lines: List(Line)) -> #(List(Attr), List(DesugaringWarning)) {
  lines
  |> list.map(harvest_handle_attrs_from_line)
  |> result.partition
}

fn harvest_handle_attrs_from_text_nodes(children: List(VXML)) -> #(List(Attr), List(DesugaringWarning)) {
  list.fold(
    children,
    #([], []),
    fn(acc, vxml) {
      case vxml {
        V(..) -> acc
        T(_, lines) -> {
          let #(hs, ws) = harvest_handle_attrs_from_lines(lines)
          // we list.reverse because result.partition does that
          #(list.append(acc.0, hs |> list.reverse), list.append(acc.1, ws |> list.reverse))
        }
      }
    }
  )
}

fn v_before_2(_: Nil, vxml: VXML) -> Result(#(Nil, List(Attr), List(DesugaringWarning), infra.TrafficLight), DesugaringError){
  let assert V(_, tag, attrs, children) = vxml

  use <- on.false_true(
    tag == "In",
    fn() { Ok(#(Nil, [], [], tag_past_root(tag))) }
  )

  use <- on.false_true(
    infra.attrs_have_key_val(attrs, "chapter", ">>exercise-graveyard"),
    fn() { Ok(#(Nil, [], [], infra.GoBack)) }
  )

  let #(attrs, warnings) = harvest_handle_attrs_from_text_nodes(children)

  Ok(#(
    Nil,
    attrs,
    warnings,
    infra.GoBack
  ))
}

fn assertive_tests_data() -> List(infra.AssertiveTestData(Param(Nil))) {
  // a,
  // // v_before
  // fn(a, VXML) -> Result(#(a, List(Attr), List(DesugaringWarning), infra.TrafficLight), DesugaringError),
  // // v_after
  // fn(a, a, VXML) -> Result(#(a, List(Attr), List(DesugaringWarning)), DesugaringError),
  // // t
  // fn(a, VXML) -> Result(#(a, List(Attr), List(DesugaringWarning)), DesugaringError),
  [
    infra.AssertiveTestData(
      param: #(
        Nil,
        v_before_1,
        v_after_1,
        t_1,
      ),
      source: "
        <> root
          <> In
            chapter=>>notme
      ",
      expected: "
        <> GrandWrapper
          <> root
            <> In
              chapter=>>notme
      ",
    ),
    infra.AssertiveTestData(
      param: #(
        Nil,
        v_before_1,
        v_after_1,
        t_1,
      ),
      source: "
        <> GrandWrapper
          <> root
            <> In
              chapter=>>notme
      ",
      expected: "
        <> GrandWrapper
          <> root
            <> In
              chapter=>>notme
      ",
    ),
    infra.AssertiveTestData(
      param: #(
        Nil,
        v_before_1,
        v_after_1,
        t_1,
      ),
      source: "
        <> root
          <> In
            chapter=>>notme
          <> In
            chapter=>>exercise-graveyard
      ",
      expected: "
        <> GrandWrapper
          hey=hello
          <> root
            <> In
              chapter=>>notme
            <> In
              chapter=>>exercise-graveyard
      ",
    ),
    infra.AssertiveTestData(
      param: #(
        Nil,
        v_before_1,
        v_after_1,
        t_1,
      ),
      source: "
        <> GrandWrapper
          <> root
            <> In
              chapter=>>notme
            <> In
              chapter=>>exercise-graveyard
      ",
      expected: "
        <> GrandWrapper
          hey=hello
          <> root
            <> In
              chapter=>>notme
            <> In
              chapter=>>exercise-graveyard
      ",
    ),
    infra.AssertiveTestData(
      param: #(
        Nil,
        v_before_2,
        v_after_1,
        t_1,
      ),
      source: "
        <> GrandWrapper
          <> root
            <> In
              chapter=>>notme
            <> In
              chapter=>>exercise-graveyard
              <>
                '>>mia'
                '>> qia '
                '!! gimme a warning'
                '>>last'
              <>
                '>>mia2'
                '>> qia2 '
                '!! gimme a warning2'
                '>>last2'
      ",
      expected: "
        <> GrandWrapper
          source=>>mia
          source=>>qia
          source=>>last
          source=>>mia2
          source=>>qia2
          source=>>last2
          <> root
            <> In
              chapter=>>notme
            <> In
              chapter=>>exercise-graveyard
              <>
                '>>mia'
                '>> qia '
                '!! gimme a warning'
                '>>last'
              <>
                '>>mia2'
                '>> qia2 '
                '!! gimme a warning2'
                '>>last2'
      ",
    ),
  ]
}

pub fn assertive_tests() {
  infra.assertive_test_collection_from_data(name, assertive_tests_data(), constructor)
}
