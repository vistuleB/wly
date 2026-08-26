import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugaringError, type DesugaringWarning, DesugaringError,
}
import desugaring/desugarers/grand_wrapper_move_nodes_to_wrapper
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import on
import vxml.{type VXML, Attr, V}

pub const name = "lbp_move_to_be_moved_to_grand_wrapper"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Collects marked LBP nodes into a `NodesBeingMoved`
/// child of the document's `GrandWrapper`.
pub fn constructor() -> Desugarer {
  authoring.no_param_desugarer(
    name: name,
    transform: grand_wrapper_move_nodes_to_wrapper.constructor(#(
      #(None, []),
      v_before_1,
      v_after_1,
      t_1,
      "NodesBeingMoved",
    )).transform,
  )
}

fn desugarer_blame(line_no: Int) {
  authoring.blame(name, line_no)
}

fn harvest_handles_2b_cut_from_grand_wrapper(vxml: VXML) -> List(String) {
  let assert V(_, "GrandWrapper", attrs, _) = vxml
  attrs
  |> list.map(fn(attr) {
    assert attr.key == "to-be-moved"
    let assert ">>" <> stuff = attr.val
    assert stuff == string.trim(stuff)
    stuff
  })
}

fn v_before_1(
  state: State,
  vxml: VXML,
) -> Result(
  #(State, Result(VXML, VXML), List(DesugaringWarning), core.TrafficLight),
  DesugaringError,
) {
  let assert V(blame, tag, attrs, _) = vxml
  let #(chapter_handle, handles_2b_cut) = state

  // try to load state.1
  let handles_2b_cut = case tag {
    "GrandWrapper" -> {
      assert chapter_handle == None
      assert handles_2b_cut == []
      harvest_handles_2b_cut_from_grand_wrapper(vxml)
    }
    _ -> handles_2b_cut
  }

  // try to load state.0
  use chapter_handle <- on.ok(case tag {
    "Chapter" | "Bootcamp" | "Appendix" -> {
      assert chapter_handle == None
      use chapter_handle <- on.ok(core.attrs_val_first_with_key_expected(
        attrs,
        "handle",
        blame,
      ))
      Ok(Some(chapter_handle))
    }
    _ -> Ok(chapter_handle)
  })

  let state = #(chapter_handle, handles_2b_cut)

  // maybe we don't have a handle or we're not one of the handles to be cut
  let #(attr, attrs) = core.attrs_extract_first(attrs, "handle")
  use attr <- on.none_some(attr, fn() {
    Ok(#(state, Ok(vxml), [], core.Continue))
  })
  let handle_name = string.trim(attr.val)
  use <- on.false_true(list.contains(handles_2b_cut, handle_name), fn() {
    case tag {
      "Section" | "Exercise" -> Ok(#(state, Ok(vxml), [], core.GoBack))
      _ -> Ok(#(state, Ok(vxml), [], core.Continue))
    }
  })

  // we're supposed to get cut --- but we freak out if chapter_handle is not defined
  use chapter_handle <- on.ok(case chapter_handle {
    None -> Error(DesugaringError(blame, "chapter_handle is still None"))
    Some(x) -> Ok(x)
  })

  // we're getting cut:
  let attr1 = Attr(..attr, val: handle_name)
  let attr2 = Attr(desugarer_blame(105), "chapter", chapter_handle)
  let vxml = V(..vxml, attrs: [attr1, attr2, ..attrs])
  Ok(#(state, Error(vxml), [], core.GoBack))
}

fn v_after_1(
  original_state: State,
  _latest_state: State,
  vxml: VXML,
) -> Result(
  #(State, Result(VXML, VXML), List(DesugaringWarning)),
  DesugaringError,
) {
  Ok(#(original_state, Ok(vxml), []))
}

fn t_1(
  state: State,
  vxml: VXML,
) -> Result(
  #(State, Result(VXML, VXML), List(DesugaringWarning)),
  DesugaringError,
) {
  Ok(#(state, Ok(vxml), []))
}

type State =
  #(Option(String), List(String))

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊

fn assertive_tests_data() -> List(core.AssertiveTestDataNoParam) {
  [
    core.AssertiveTestDataNoParam(
      source: "
        <> GrandWrapper
          to-be-moved=>>koolio
          to-be-moved=>>koolio2
          to-be-moved=>>koolio4
          <> Book
            <> Chapter
              handle=ch1
              <> SomeGuy
              <> ShallBeMoved
                handle=koolio
              <> OtherShallBeMoved
                handle=koolio2
            <> Chapter
              handle=ch2
              <> ShallNotBeMoved
                handle=koolio3
              <> ThirdShallBeMoved
                handle=koolio4
      ",
      expected: "
        <> GrandWrapper
          to-be-moved=>>koolio
          to-be-moved=>>koolio2
          to-be-moved=>>koolio4
          <> NodesBeingMoved
            <> ShallBeMoved
              handle=koolio
              chapter=ch1
            <> OtherShallBeMoved
              handle=koolio2
              chapter=ch1
            <> ThirdShallBeMoved
              handle=koolio4
              chapter=ch2
          <> Book
            <> Chapter
              handle=ch1
              <> SomeGuy
            <> Chapter
              handle=ch2
              <> ShallNotBeMoved
                handle=koolio3
      ",
    ),
  ]
}

pub fn assertive_tests() {
  core.assertive_test_collection_from_data_no_param(
    name,
    assertive_tests_data(),
    constructor,
  )
}
