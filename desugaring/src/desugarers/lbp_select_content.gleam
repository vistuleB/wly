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
  Desugarer,
} as infra
import vxml.{type VXML, V}
import blame as bl
import nodemaps_2_desugarer_transforms as n2t
import on

fn with_handle_value(thing: VXML) -> Result(#(String, VXML), DesugaringError) {
  let assert V(blame, tag, attrs, _) = thing
  case infra.attrs_val_of_unique_key(attrs, "handle", blame) {
    Error(_) -> Error(DesugaringError(blame, "'" <> tag <> "' tag missing handle attribute"))
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

fn set_exercises_to(chapter: VXML, handles: List(String)) -> Result(VXML, DesugaringError) {
  let assert V(_, _, _, children) = chapter
  // use title <- on.ok(infra.attrs_val_of_unique_key(attrs, "title", blame))
  let #(exercises_node, other_children) = case children |> list.reverse {
    [V(_, "Exercises", _, _) as first, ..rest] -> #(first, rest)
    rest -> #(V(desugarer_blame(43), "Exercises", [], []), rest)
  }
  let assert V(_, "Exercises", _, exercises) = exercises_node
  use handle_2_exercise_dict <- on.ok(
    exercises
    |> list.filter(infra.is_v_and_tag_equals(_, "Exercise"))
    |> list.try_map(with_handle_value)
    |> result.map(dict.from_list)
  )
  use exercises <- on.ok(list.try_map(
    handles,
    fn(handle) {
      case dict.get(handle_2_exercise_dict, handle) {
        Ok(x) -> Ok(x)
        _ -> Error(DesugaringError(desugarer_blame(57), "no Exercise with handle '" <> handle <> "'"))
      }
    }
  ))
  let exercises_node = V(..exercises_node, children: exercises)
  Ok(V(..chapter, children: [exercises_node, ..other_children] |> list.reverse))
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
    case others {
      [
        V(_, "ChapterSelection", _, _) as first,
        ..,
      ] -> Ok(first)
      _ -> Error(Nil)
    },
    fn(_) { Ok(#(V(..root, children: chapters), [])) }
  )

  let selected_chapter_handles = {
    let assert V(_, _, _, children) = chapter_selection_node
    children
    |> list.map(infra.descendant_lines)
    |> list.flatten
    |> list.map(fn(line) {
      assert string.starts_with(line.content, ">>")
      string.drop_start(line.content, 2)
    })
  }

  use chapters <- on.ok(list.try_map(
    selected_chapter_handles,
    fn(handle) {
      use exercise_handles <- on.ok(
        case dict.get(handle_2_in_elts_dict, handle) {
          Ok(in_elt) -> {
            let assert V(_, "In", _, children) = in_elt
            children
            |> list.map(infra.descendant_lines)
            |> list.flatten
            |> list.map(fn(line) {
              assert string.starts_with(line.content, ">>")
              string.drop_start(line.content, 2)
            })
            |> Ok
          }
          Error(Nil) -> {
            Ok([])
            // Error(DesugaringError(desugarer_blame(133), "no 'In' element with handle '" <> handle <> "'"))
          }
        }
      )
      use chapter <- on.error_ok(
        dict.get(handle_2_chapter_dict, handle),
        fn(_) { Error(DesugaringError(desugarer_blame(139), "no chapter with handle '" <> handle <> "'")) }
      )
      set_exercises_to(chapter, exercise_handles)
    }
  ))

  Ok(#(V(..root, children: chapters), []))
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
