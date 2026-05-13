import gleam/result
import gleam/list
import gleam/string
import gleam/option
import infrastructure.{
  type Desugarer,
  type DesugaringError,
  type DesugaringWarning,
  DesugaringWarning,
  DesugaringError,
  Desugarer,
} as infra
import vxml.{type Attr, type VXML, V, T, Attr, type Line}
import on
import desugarers/grand_wrapper_append_attributes
import blame as bl

fn harvest_handle_attrs_from_line(line: Line) -> Result(Attr, DesugaringWarning) {
  case line.content {
    ">>" <> stuff -> {
      let stuff = string.trim(stuff)
      case string.contains(stuff, " ") || string.contains(stuff, ">") {
        True -> Error(DesugaringWarning(line.blame, "handle contains space or '>': " <> stuff))
        False -> Ok(Attr(desugarer_blame(24), "to-be-moved", ">>" <> stuff))
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

fn v_before(_: Nil, vxml: VXML) -> Result(#(Nil, List(Attr), List(DesugaringWarning), infra.TrafficLight), DesugaringError) {
  let assert V(blame, tag, attrs, children) = vxml

  use _ <- on.stay(case tag {
    // cases we Continue
    "GrandWrapper" | "Book" -> on.Return(Ok(#(Nil, [], [], infra.Continue)))
    // case we process
    "In" -> on.Stay(Nil)
    // cases we GoBack
    _ -> on.Return(Ok(#(Nil, [], [], infra.GoBack)))
    // unexpected -- to be thought about
    // _ -> on.Return(Error(DesugaringError(blame, "unexpected tag: '" <> tag <> "'")))
  })

  use chapter_handle <- on.ok(infra.attrs_val_first_with_key_expected(attrs, "chapter", blame))
  let assert ">>" <> chapter_handle = chapter_handle
        
  use _ <- on.stay(case chapter_handle {
    "exercise-graveyard" -> on.Stay(Nil)
    _ -> on.Return(Ok(#(Nil, [], [], infra.GoBack)))
  })

  let #(attrs, warnings) = harvest_handle_attrs_from_text_nodes(children)

  Ok(#(
    Nil,
    attrs,
    warnings,
    infra.GoBack
  ))
}

fn v_after(_: Nil, _: Nil, _vxml: VXML) -> Result(#(Nil, List(Attr), List(DesugaringWarning)), DesugaringError) {
  Ok(#(Nil, [], []))
}

fn t_transform(_: Nil, _vxml: VXML) -> Result(#(Nil, List(Attr), List(DesugaringWarning)), DesugaringError) {
  Ok(#(Nil, [], []))
}

pub const name = "lbp_exercise_graveyard_generate_grand_wrapper_to_be_moved_attributes"
fn desugarer_blame(line_no: Int) { bl.Des([], name, line_no) }

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
pub fn constructor() -> Desugarer {
  Desugarer(
    name: name,
    stringified_param: option.None,
    stringified_outside: option.None,
    transform: grand_wrapper_append_attributes.constructor(
      #(
        Nil,
        v_before,
        v_after,
        t_transform,
      )
    ).transform,
  )
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊

fn assertive_tests_data() -> List(infra.AssertiveTestDataNoParam) {
  [
    infra.AssertiveTestDataNoParam(
      source: "
        <> Book
          <> In
            chapter=>>functions
            <>
              '>>blabla'
          <> In
            chapter=>>exercise-graveyard
            <>
              '>>blabla2'
              '>>blabla3'
            <> WriterlyBlankLine
            <> WriterlyComment
            <>
              '>>blabla4'
      ",
      expected: "
        <> GrandWrapper
          to-be-moved=>>blabla2
          to-be-moved=>>blabla3
          to-be-moved=>>blabla4
          <> Book
            <> In
              chapter=>>functions
              <>
                '>>blabla'
            <> In
              chapter=>>exercise-graveyard
              <>
                '>>blabla2'
                '>>blabla3'
              <> WriterlyBlankLine
              <> WriterlyComment
              <>
                '>>blabla4'
      ",
    ),
  ]
}

pub fn assertive_tests() {
  infra.assertive_test_collection_from_data_no_param(name, assertive_tests_data(), constructor)
}
