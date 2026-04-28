import gleam/dict
import gleam/option.{Some, None}
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
  let assert V(blame, _, attrs, _) = thing
  case infra.attrs_val_of_unique_key(attrs, "handle", blame) {
    Error(_) -> Ok(#("", thing))
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

fn exercise_filterer_nodemap(node: VXML, handles: List(String)) -> List(VXML) {
  case node {
    V(_, "Exercises", _, []) -> []
      V(_, "Exercise", attrs, _) -> case infra.attrs_first_with_key(attrs, "handle") {
      None -> [node]
      Some(x) -> case list.contains(handles, x.val) {
        True -> [node]
        False -> []
      }
    }
    _ -> [node]
  }
}

fn set_exercises_to(chapter: VXML, handles: List(String)) -> Result(#(VXML, List(DesugaringWarning)), DesugaringError) {
  let nodemap = exercise_filterer_nodemap(_, handles)
  case n2t.one_to_many_no_error_nodemap_walk(chapter, nodemap) {
    [root] -> Ok(#(root, []))
    [] -> Error(DesugaringError(desugarer_blame(56), "empty chapter after filtering exercises"))
    _ -> panic as "nodemap walk returned list with > 1 node (???)"
  }
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

  use chapter_selection_node <- on.eager_error_ok(
    list.find(
      others,
      infra.is_v_and_tag_equals(_, "ChapterSelection"),
    ),
    Error(DesugaringError(desugarer_blame(150), "'ChapterSelection' node not found")),
  )

  let handles_of_selected_chapters = {
    let assert V(_, _, _, children) = chapter_selection_node
    children
    |> list.flat_map(infra.descendant_lines)
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
      handles_of_selected_chapters,
      #([], []),
      fn(acc, handle) {
        use exercise_handles <- on.stay(
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
              |> on.Stay
            }
            Error(Nil) -> {
              let warning = DesugaringWarning(desugarer_blame(160), "no '|> In' exercise list found for chapter '" <> handle <> "'")
              on.Return(Ok(#(acc.0, [warning, ..acc.1])))
            }
          }
        )

        use chapter <- on.error_ok(
          dict.get(handle_2_chapter_dict, handle),
          fn(_) {
            Ok(#(
              acc.0,
              [DesugaringWarning(desugarer_blame(171), "no '|> In' exercise list found for chapter '" <> handle <> "'"), ..acc.1],
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
