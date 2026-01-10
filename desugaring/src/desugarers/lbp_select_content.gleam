import gleam/dict
import gleam/option
import gleam/list
import gleam/result
import gleam/string
import infrastructure.{
  type Desugarer,
  type DesugarerTransform,
  type DesugaringError,
  type DesugaringWarning,
  DesugaringError,
  DesugaringWarning,
  Desugarer,
} as infra
import vxml.{type VXML, V}
import blame as bl
import nodemaps_2_desugarer_transforms as n2t
import on

fn with_handle_value(thing: VXML) -> Result(#(String, VXML), DesugaringError) {
  let assert V(blame, tag, attrs, _) = thing
  case infra.attrs_val_of_unique_key(attrs, "handle", blame) {
    Error(_) -> {
      // Ok(#("", thing))
      Error(DesugaringError(blame, "'" <> tag <> "' tag missing handle attribute"))
    }
    Ok(x) -> Ok(#(x, thing))
  }
}

fn with_chapter_value(thing: VXML) -> Result(#(String, VXML), DesugaringError) {
  let assert V(blame, tag, attrs, _) = thing
  case infra.attrs_val_of_unique_key(attrs, "chapter", blame) {
    Error(_) -> Error(DesugaringError(blame, "'" <> tag <> "' tag missing 'chapter' attribute"))
    Ok(x) -> {
      assert string.starts_with(x, ">>")
      Ok(#(x |> string.drop_start(2), thing))
    }
  }
}

fn set_exercises_to(chapter: VXML, handles: List(String)) -> Result(#(VXML, List(DesugaringWarning)), DesugaringError) {
  let assert V(_, _, _, children) = chapter
  let #(exercises_node, other_children) = case children |> list.reverse {
    [V(_, "Exercises", _, _) as first, ..rest] -> #(first, rest)
    rest -> #(V(desugarer_blame(43), "Exercises", [], []), rest)
  }
  let assert V(_, "Exercises", _, exercises) = exercises_node
  use handle_2_exercise_dict <- on.ok(
    exercises
    |> list.filter(infra.is_v_and_tag_equals(_, "Exercise"))
    |> list.try_map(with_handle_value)
    |> result.map(fn(pairs) { list.filter(pairs, fn(pair) {pair.0 != ""})})
    |> result.map(dict.from_list)
  )
  let #(exercises, warnings) = list.fold(
    handles,
    #([], []),
    fn(acc, handle) {
      let #(exercises, warnings) = acc
      case dict.get(handle_2_exercise_dict, handle) {
        Ok(x) -> #([x, ..exercises], warnings)
        _ -> {
          let warning = DesugaringWarning(desugarer_blame(57), "no Exercise with handle '" <> handle <> "'")
          #(exercises, [warning, ..warnings])
        }
      }
    }
  )

  let children = case exercises {
    [] -> other_children |> list.reverse
    _ -> {
      let exercises_node = V(..exercises_node, children: exercises |> list.reverse)
      [exercises_node, ..other_children] |> list.reverse
    }
  }

  Ok(#(
    V(..chapter, children: children),
    warnings,
  ))
}

fn at_root(root: VXML) -> Result(#(VXML, List(DesugaringWarning)), DesugaringError) {
  let assert V(_, "Book", _, children) = root

  // need to construct two dictionaries
  // - handles-to-chapters
  // - handles-to-exercises

  let #(chapters, others) = list.partition(
    children,
    infra.is_v_and_tag_is_one_of(_, ["Chapter", "Bootcamp"]),
  )

  let #(in_elts, others) = list.partition(
    others,
    infra.is_v_and_tag_equals(_, "In"),
  )

  use handle_2_chapter_dict <- on.ok(
    chapters
    |> list.try_map(with_handle_value)
    |> result.map(dict.from_list)
  )

  use handle_2_in_elts_dict <- on.ok(
    in_elts
    |> list.map(with_chapter_value)
    |> result.all
    |> result.map(dict.from_list)
  )

  use chapter_selection_node <- on.error_ok(
    list.find(
      others,
      infra.is_v_and_tag_equals(_, "ChapterSelection"),
    ),
    fn(_) { Ok(#(V(..root, children: chapters), [])) },
  )

  let selected_chapter_handles = {
    let assert V(_, _, _, children) = chapter_selection_node
    children
    |> list.map(infra.descendant_lines)
    |> list.flatten
    |> list.map(fn(line) {
      assert string.starts_with(line.content, ">>")
      let content = string.drop_start(line.content, 2)
      case string.split_once(content, " ") {
        Ok(#(t, _)) -> t
        Error(_) -> content
      }
    })
  }

  use #(chapters, warnings) <- on.ok(
    list.try_fold(
      selected_chapter_handles,
      #([], []),
      fn(acc, handle) {
        use exercise_handles <- on.select(
          case dict.get(
            handle_2_in_elts_dict,
            handle,
          ) {
            Ok(in_elt) -> {
              let assert V(_, "In", _, children) = in_elt
              children
              |> list.map(infra.descendant_lines)
              |> list.flatten
              |> list.map(fn(line) {
                assert string.starts_with(line.content, ">>")
                string.drop_start(line.content, 2)
              })
              |> on.Select
            }
            Error(Nil) -> {
              let warning = DesugaringWarning(desugarer_blame(178), "no '|> In' exercise list found for chapter '" <> handle <> "'")
              on.Return(Ok(#(acc.0, [warning, ..acc.1])))
            }
          }
        )

        use chapter <- on.error_ok(
          dict.get(handle_2_chapter_dict, handle),
          fn(_) {
            Ok(#(
              acc.0,
              [DesugaringWarning(desugarer_blame(178), "no '|> In' exercise list found for chapter '" <> handle <> "'"), ..acc.1],
            ))
          }
        )

        use #(chapter, warnings) <- on.ok(set_exercises_to(chapter, exercise_handles))
        #([chapter, ..acc.0], list.append(acc.1, warnings)) |> Ok
      }
    )
  )

  Ok(#(V(..root, children: chapters |> list.reverse), warnings))
}

fn desugarer_factory(_inner: InnerParam) -> infra.DesugarerTransform {
  at_root(_)
  |> n2t.at_root_with_warnings_2_desugarer_transform
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(param)
}

type Param = Nil
type InnerParam = Param

pub const name = "lbp_select_content"
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
    transform: case param_to_inner_param(Nil) {
      Error(error) -> fn(_) { Error(error) }
      Ok(inner) -> desugarer_factory(inner)
    }
  )
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
fn assertive_tests_data() -> List(infra.AssertiveTestDataNoParam) {
  []
}

pub fn assertive_tests() {
  infra.assertive_test_collection_from_data_no_param(name, assertive_tests_data(), constructor)
}
