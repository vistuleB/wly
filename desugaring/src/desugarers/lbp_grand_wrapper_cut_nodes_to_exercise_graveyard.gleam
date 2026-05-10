import gleam/list
import gleam/dict.{type Dict}
import gleam/option.{Some}
import infrastructure.{
  type Desugarer,
  type DesugarerTransform,
  type DesugaringError,
  type DesugaringWarning,
  DesugaringWarning,
  Desugarer,
} as infra
import nodemaps_2_desugarer_transforms as n2t
import vxml.{type VXML, V}
import on

fn load_cut_nodes(vxml: VXML) -> Dict(String, List(VXML)) {
  let assert V(_, "GrandWrapper", _, children) = vxml
  let assert Ok(cut_nodes) = list.find(children, infra.is_v_and_tag_equals(_, "NodesBeingMoved"))
  let assert V(_, "NodesBeingMoved", _, cut_nodes) = cut_nodes
  list.fold(
    cut_nodes,
    [] |> dict.from_list,
    fn(acc, node) {
      let assert V(_, "Exercise", attrs, _) = node
      let assert Ok(#(Some(attr), attrs)) = infra.attrs_extract_unique_key_or_none(attrs, "chapter")
      let node = V(..node, attrs: attrs)
      case dict.get(acc, attr.val) {
        Ok(some_list) -> dict.insert(acc, attr.val, [node, ..some_list])
        Error(_) -> dict.insert(acc, attr.val, [node])
      }
    }
  )
}

fn v_before_transforming_children(
  vxml: VXML,
  state: State,
) -> Result(#(VXML, State, List(DesugaringWarning), infra.TrafficLight), DesugaringError) {
  let state = case state.0 {
    True -> state
    False -> #(True, load_cut_nodes(vxml))
  }
  // cases we should not GoBack:
  // - GrandWrapper
  // - Book
  // - Appendix handle=exercise-graveyard
  let assert V(blame, tag, attrs, children) = vxml
  use _ <- on.stay(case tag {
    "GrandWrapper" | "Book" -> on.Return(Ok(#(vxml, state, [], infra.Continue)))
    "Appendix" -> case infra.attrs_val_first_with_key(attrs, "handle") {
      Some("exercise-graveyard") -> on.Return(Ok(#(vxml, state, [], infra.Continue)))
      _ -> on.Return(Ok(#(vxml, state, [], infra.GoBack)))
    }
    "Exercises" -> on.Stay(Nil)
    _ -> on.Return(Ok(#(vxml, state, [], infra.GoBack)))
  })
  assert tag == "Exercises"
  use chapter_handle <- on.ok(infra.attrs_val_first_with_key_expected(attrs, "chapter", blame))
  let assert ">>" <> chapter_handle = chapter_handle
  let #(exercises, warnings) = case dict.get(state.1, chapter_handle) {
    Ok(exercises) -> #(exercises, [])
    _ -> #([], [DesugaringWarning(blame, "could not find any exercises for chapter '" <> chapter_handle <> "'")])
  }
  // nb: exercises are in reversed order inside the dict...
  let children = infra.pour(exercises, children)
  let vxml = V(blame, tag, attrs, children)
  Ok(#(vxml, state, warnings, infra.GoBack))
}

fn v_after_transforming_children(
  vxml: VXML,
  original_state: State,
  latest_state: State,
) -> Result(#(VXML, State, List(DesugaringWarning)), DesugaringError) {
  case original_state.0 {
    False -> {
      let assert V(_, "GrandWrapper", _, children) = vxml
      let assert Ok(book) = list.find(children, infra.is_v_and_tag_equals(_, "Book"))
      Ok(#(book, latest_state, []))
    }
    True -> Ok(#(vxml, latest_state, []))
  }
}

fn t_transform(
  vxml: VXML,
  state: State,
) -> Result(#(VXML, State, List(DesugaringWarning)), DesugaringError) {
  Ok(#(vxml, state, []))
}

fn nodemap_factory(_inner: InnerParam) -> n2t.EarlyReturnOneToOneBeforeAndAfterStatefulNodemapWithWarnings(State) {
   n2t.EarlyReturnOneToOneBeforeAndAfterStatefulNodemapWithWarnings(
    v_before_transforming_children: v_before_transforming_children,
    v_after_transforming_children: v_after_transforming_children,
    t_nodemap: t_transform,
  )
}

fn transform_factory(inner: InnerParam) -> infra.DesugarerTransform {
  n2t.early_return_one_to_one_before_and_after_stateful_nodemap_with_warnings_2_desugarer_transform(
    nodemap_factory(inner),
    #(False, [] |> dict.from_list),
  )
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(param)
}

type State = #(Bool, Dict(String, List(VXML)))

type Param = Nil
type InnerParam = Param

pub const name = "lbp_grand_wrapper_cut_nodes_to_exercise_graveyard"
// fn desugarer_blame(line_no: Int) { bl.Des([], name, line_no) }

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
pub fn constructor() -> Desugarer {
  Desugarer(
    name: name,
    stringified_param: option.None,
    stringified_outside: option.None,
    transform: case param_to_inner_param(Nil) {
      Error(error) -> fn(_) { Error(error) }
      Ok(inner) -> transform_factory(inner)
    },
  )
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊

fn assertive_tests_data() -> List(infra.AssertiveTestDataNoParam) {
  [
    infra.AssertiveTestDataNoParam(
      source: "
        <> GrandWrapper
          <> NodesBeingMoved
            <> Exercise
              handle=calami
              chapter=functions
              <>
                'Hello from calami.'
              <> Solution
                <>
                  'Calami's solution.'
            <> Exercise
              chapter=functions
              <>
                'Hello from no-handle.'
            <> Exercise
              chapter=derivatives
              <>
                'Hello from no-handle in derivatives chapter.'
          <> Book
            <> Chapter
              <> Section
              <> Section
            <> Appendix
              handle=not-the-right-appendix
              <> Exercises
                chapter=functions
                chapter=derivatives
            <> Appendix
              handle=exercise-graveyard
              <>
                'some text node A'
              <>
                'some text node B'
              <> Exercises
                chapter=>>functions
              <> Exercises
                chapter=>>derivatives
              <> Exercises
                chapter=>>nonexistent
      ",
      expected: "
        <> Book
          <> Chapter
            <> Section
            <> Section
          <> Appendix
            handle=not-the-right-appendix
            <> Exercises
              chapter=functions
              chapter=derivatives
          <> Appendix
            handle=exercise-graveyard
            <>
              'some text node A'
            <>
              'some text node B'
            <> Exercises
              chapter=>>functions
              <> Exercise
                handle=calami
                <>
                  'Hello from calami.'
                <> Solution
                  <>
                    'Calami's solution.'
              <> Exercise
                <>
                  'Hello from no-handle.'
            <> Exercises
              chapter=>>derivatives
              <> Exercise
                <>
                  'Hello from no-handle in derivatives chapter.'
            <> Exercises
              chapter=>>nonexistent
      ",
    ),
  ]
}

pub fn assertive_tests() {
  infra.assertive_test_collection_from_data_no_param(name, assertive_tests_data(), constructor)
}
