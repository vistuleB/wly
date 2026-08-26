import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
  type DesugaringWarning, DesugaringError, DesugaringWarning,
}
import desugaring/nodemaps_2_transform as n2t
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/order
import gleam/result
import gleam/string
import on
import vxml.{type VXML, V}
import vxml/blame as bl

pub const name = "lbp_select_content"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Selects and orders the LBP content requested by the
/// document's selection metadata.
pub fn constructor() -> Desugarer {
  authoring.no_param_desugarer(
    name: name,
    transform: inner_param_to_transform(Nil),
  )
}

type InnerParam =
  Nil

fn inner_param_to_transform(_inner: InnerParam) -> core.DesugarerTransform {
  at_root
  |> n2t.node_to_node_with_warnings_2_desugarer_transform_without_walking
}

fn desugarer_blame(line_no: Int) {
  authoring.blame(name, line_no)
}

fn with_handle_value(thing: VXML) -> Result(#(String, VXML), DesugaringError) {
  let assert V(blame, _, attrs, _) = thing
  case core.attrs_val_of_unique_key(attrs, "handle", blame) {
    Error(_) -> Ok(#("", thing))
    Ok(x) -> Ok(#(x, thing))
  }
}

fn with_chapter_value(thing: VXML) -> Result(#(String, VXML), DesugaringError) {
  let assert V(blame, tag, attrs, _) = thing
  case core.attrs_val_of_unique_key(attrs, "chapter", blame) {
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

fn exercise_filterer_nodemap(
  node: VXML,
  handles: List(String),
) -> #(List(VXML), List(DesugaringWarning)) {
  case node {
    V(_, "Exercise", attrs, _) ->
      case core.attrs_first_with_key(attrs, "handle") {
        None -> #([], [
          DesugaringWarning(
            desugarer_blame(77),
            "removing Exercise node w/out handle",
          ),
        ])
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
  let #(exercises, children) =
    list.map_fold(children, [], fn(acc, child) {
      case child {
        V(_, "Exercise", _, _) -> #([child, ..acc], dummy)
        _ -> #(acc, child)
      }
    })

  // return if no such children:
  use _ <- on.stay(case exercises {
    [] -> on.Return(node)
    _ -> on.Stay(Nil)
  })

  // sort
  let exercises = list.sort(exercises, ranker)

  // re-insert:
  let #(exercises, children) =
    list.map_fold(children, exercises, fn(acc, child) {
      case child {
        V(_, "DumDum", _, _) -> {
          let assert [exercise, ..more] = acc
          #(more, exercise)
        }
        _ -> #(acc, child)
      }
    })
  assert exercises == []
  let assert V(..) = node
  V(..node, children: children)
}

fn set_exercises_to(
  chapter: VXML,
  handles: List(String),
) -> Result(#(VXML, List(DesugaringWarning)), DesugaringError) {
  let nodemap = exercise_filterer_nodemap(_, handles)
  let #(root, warnings) =
    n2t.one_to_many_no_error_with_warnings_nodemap_walk(chapter, nodemap)
  use root <- on.stay(case root {
    [root] -> on.Stay(root)
    [] ->
      on.Return(
        Error(DesugaringError(
          desugarer_blame(154),
          "empty chapter after filtering exercises",
        )),
      )
    _ -> panic as "nodemap walk returned list with > 1 node (???)"
  })
  let exercises_dict = create_handles_rank_dict(handles)
  let exercise_comparer = fn(a: VXML, b: VXML) -> order.Order {
    let assert V(_, "Exercise", attrs_a, _) = a
    let assert V(_, "Exercise", attrs_b, _) = b
    let assert Some(handle_a) = core.attrs_val_first_with_key(attrs_a, "handle")
    let assert Some(handle_b) = core.attrs_val_first_with_key(attrs_b, "handle")
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
      core.is_v_and_tag_is_one_of(_, ["Chapter", "Bootcamp", "Appendix"]),
    )

  let #(in_elts, others) =
    list.partition(others, core.is_v_and_tag_equals(_, "In"))

  let #(to_keep, others) =
    list.partition(others, core.is_v_and_tag_equals(_, "HeaderBlob"))

  use handle_2_chapter_dict <- on.ok(
    chapters
    |> list.try_map(with_handle_value)
    |> result.map(dict.from_list),
  )

  use handle_2_in_elts_dict <- on.ok(
    in_elts
    |> list.try_map(with_chapter_value)
    |> result.map(dict.from_list),
  )

  use chapter_selection_node <- on.eager_error_ok(
    list.find(others, core.is_v_and_tag_equals(_, "ChapterSelection")),
    Error(DesugaringError(
      desugarer_blame(211),
      "'ChapterSelection' node not found",
    )),
  )

  let handles_of_selected_chapters = {
    let assert V(_, _, _, children) = chapter_selection_node
    children
    |> list.flat_map(core.descendant_lines)
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
      use chapter <- on.error_ok(
        dict.get(handle_2_chapter_dict, handle),
        on_error: fn(_) {
          let warning =
            DesugaringWarning(
              desugarer_blame(237),
              "found no chapter with handle '" <> handle <> "'",
            )
          Ok(#(acc.0, [warning, ..acc.1]))
        },
      )
      use in_elt <- on.error_ok(
        dict.get(handle_2_in_elts_dict, handle),
        on_error: fn(_) {
          let warning =
            DesugaringWarning(
              desugarer_blame(248),
              "no '|> In' exercise list found for chapter '" <> handle <> "'",
            )
          Ok(#([chapter, ..acc.0], [warning, ..acc.1]))
        },
      )
      let assert V(_, "In", _, in_elt_children) = in_elt
      let exercise_handles =
        in_elt_children
        |> list.flat_map(core.descendant_lines)
        |> list.map(fn(line) {
          assert string.starts_with(line.content, ">>")
          string.drop_start(line.content, 2)
        })
      use #(chapter, warnings) <- on.ok(set_exercises_to(
        chapter,
        exercise_handles,
      ))
      #([chapter, ..acc.0], list.append(acc.1, warnings)) |> Ok
    }),
  )

  use _, _ <- on.empty_nonempty(chapters, fn() {
    Error(DesugaringError(bl.no_blame, "no chapters found"))
  })

  Ok(#(
    V(..root, children: chapters |> list.reverse |> list.append(to_keep, _)),
    warnings,
  ))
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊

fn assertive_tests_data() -> List(core.AssertiveTestDataNoParam) {
  []
}

pub fn assertive_tests() {
  core.assertive_test_collection_from_data_no_param(
    name,
    assertive_tests_data(),
    constructor,
  )
}
