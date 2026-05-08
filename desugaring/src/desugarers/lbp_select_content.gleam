import blame as bl
import gleam/dict.{type Dict}
import gleam/list
import gleam/int
import gleam/option.{None, Some}
import gleam/order
import gleam/result
import gleam/string
import infrastructure.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
  type DesugaringWarning, Desugarer, DesugaringError, DesugaringWarning,
} as infra
import nodemaps_2_desugarer_transforms as n2t
import on
import vxml.{type VXML, V}

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
    Error(_) ->
      Error(DesugaringError(
        blame,
        "'" <> tag <> "' tag missing 'chapter' attribute",
      ))
    Ok(x) -> {
      assert string.starts_with(x, ">>")
      Ok(#(x |> string.drop_start(2), thing))
    }
  }
}

fn exercise_filterer_nodemap(node: VXML, handles: List(String)) -> #(List(VXML), List(DesugaringWarning)) {
  case node {
    V(_, "Exercise", attrs, _) ->
      case infra.attrs_first_with_key(attrs, "handle") {
        None -> #([], [DesugaringWarning(desugarer_blame(44), "removing Exercise node w/out handle")])
        Some(x) ->
          case list.contains(handles, x.val) {
            True -> #([node], [])
            False -> #([], [])
          }
      }
    _ -> #([node], [])
  }
}

fn create_handles_rank_dict(handles: List(String)) -> Dict(String, Int) {
  handles
  |> list.index_map(fn(handle, idx) { #(handle, idx) })
  |> dict.from_list
}

fn rearrange_exercise_children(
  node: VXML,
  ranker: fn(VXML, VXML) -> order.Order,
) -> VXML {
  // return if we're not a V:
  use children <- on.stay(case node {
    V(..) -> on.Stay(node.children)
    _ -> on.Return(node)
  })

  // extract "Exercise" children:
  let dummy = V(bl.no_blame, "DumDum", [], [])
  let #(exercises, children) = list.map_fold(
    children,
    [],
    fn(acc, child) {
      case child {
        V(_, "Exercise", _, _) -> #([child, ..acc], dummy)
        _ -> #(acc, child)
      }
    }
  )

  // return if no such children:
  use _ <- on.stay(case exercises {
    [] -> on.Return(node)
    _ -> on.Stay(Nil)
  })

  // sort
  let exercises = list.sort(exercises, ranker)

  // re-insert:
  let #(exercises, children) = list.map_fold(
    children,
    exercises,
    fn(acc, child) {
      case child {
        V(_, "DumDum", _, _) -> {
          let assert [exercise, ..more] = acc
          #(more, exercise)
        }
        _ -> #(acc, child)
      }
    }
  )
  assert exercises == []
  let assert V(..) = node
  V(..node, children: children)
}

fn set_exercises_to(
  chapter: VXML,
  handles: List(String),
) -> Result(#(VXML, List(DesugaringWarning)), DesugaringError) {
  let nodemap = exercise_filterer_nodemap(_, handles)
  let #(root, warnings) = n2t.one_to_many_no_error_with_warnings_nodemap_walk(chapter, nodemap)
  use root <- on.stay(
    case root {
      [root] -> on.Stay(root)
      [] -> on.Return(
        Error(DesugaringError(
          desugarer_blame(123),
          "empty chapter after filtering exercises",
        ))
      )
      _ -> panic as "nodemap walk returned list with > 1 node (???)"
    },
  )
  let exercises_dict = create_handles_rank_dict(handles)
  let exercise_comparer = fn(a: VXML, b: VXML) -> order.Order {
    let assert V(_, "Exercise", attrs_a, _) = a
    let assert V(_, "Exercise", attrs_b, _) = b
    let assert Some(handle_a) = infra.attrs_val_of_first_with_key(attrs_a, "handle")
    let assert Some(handle_b) = infra.attrs_val_of_first_with_key(attrs_b, "handle")
    let assert Ok(index_a) = dict.get(exercises_dict, handle_a)
    let assert Ok(index_b) = dict.get(exercises_dict, handle_b)
    int.compare(index_a, index_b)
  }
  let nodemap = rearrange_exercise_children(_, exercise_comparer)
  let root = n2t.one_to_one_no_error_nodemap_walk(root, nodemap)
  Ok(#(root, warnings))
}

fn at_root(
  root: VXML,
) -> Result(#(VXML, List(DesugaringWarning)), DesugaringError) {
  let assert V(_, "Book", _, children) = root

  // need to construct two dictionaries
  // - handles-to-chapters
  // - handles-to-exercises

  let #(chapters, others) =
    list.partition(
      children,
      infra.is_v_and_tag_is_one_of(_, ["Chapter", "Bootcamp"]),
    )

  let #(in_elts, others) =
    list.partition(others, infra.is_v_and_tag_equals(_, "In"))

  use handle_2_chapter_dict <- on.ok(
    chapters
    |> list.try_map(with_handle_value)
    |> result.map(dict.from_list),
  )

  use handle_2_in_elts_dict <- on.ok(
    in_elts
    |> list.map(with_chapter_value)
    |> result.all
    |> result.map(dict.from_list),
  )

  use chapter_selection_node <- on.eager_error_ok(
    list.find(others, infra.is_v_and_tag_equals(_, "ChapterSelection")),
    Error(DesugaringError(
      desugarer_blame(179),
      "'ChapterSelection' node not found",
    )),
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
    list.try_fold(handles_of_selected_chapters, #([], []), fn(acc, handle) {
      use exercise_handles <- on.stay(
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
            |> on.Stay
          }
          Error(Nil) -> {
            let warning =
              DesugaringWarning(
                desugarer_blame(216),
                "no '|> In' exercise list found for chapter '" <> handle <> "'",
              )
            on.Return(Ok(#(acc.0, [warning, ..acc.1])))
          }
        },
      )

      use chapter <- on.error_ok(dict.get(handle_2_chapter_dict, handle), fn(_) {
        Ok(
          #(acc.0, [
            DesugaringWarning(
              desugarer_blame(228),
              "no '|> In' exercise list found for chapter '" <> handle <> "'",
            ),
            ..acc.1
          ]),
        )
      })

      use #(chapter, warnings) <- on.ok(set_exercises_to(
        chapter,
        exercise_handles,
      ))
      #([chapter, ..acc.0], list.append(acc.1, warnings)) |> Ok
    }),
  )

  Ok(#(V(..root, children: chapters |> list.reverse), warnings))
}

fn desugarer_factory(_inner: InnerParam) -> infra.DesugarerTransform {
  at_root
  |> n2t.at_root_with_warnings_2_desugarer_transform
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(param)
}

type Param =
  Nil

type InnerParam =
  Param

pub const name = "lbp_select_content"

fn desugarer_blame(line_no: Int) {
  bl.Des([], name, line_no)
}

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
    },
  )
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
fn assertive_tests_data() -> List(infra.AssertiveTestDataNoParam) {
  []
}

pub fn assertive_tests() {
  infra.assertive_test_collection_from_data_no_param(
    name,
    assertive_tests_data(),
    constructor,
  )
}
