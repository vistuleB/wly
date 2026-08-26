import desugaring/authoring
import desugaring/core.{type Desugarer, type DesugaringError, DesugaringError}
import desugaring/nodemaps_2_transform as n2t
import gleam/list
import gleam/string.{inspect as ins}
import on
import vxml.{type VXML, Attr, V}

fn prepend_link(vxml: VXML, link_value: String, link_key: String) -> VXML {
  core.v_prepend_attr(vxml, Attr(vxml.blame, link_key, link_value))
}

fn add_links_to_chapter(
  vxml: VXML,
  number: Int,
  num_chapters: Int,
  num_appendices: Int,
) -> VXML {
  let assert True = number >= 1 && number <= num_chapters
  let prev_link = case number == 1 {
    True -> "/"
    False -> "/article/chapter" <> ins(number - 1)
  }
  let next_link = case number == num_chapters {
    True ->
      case num_appendices > 0 {
        True -> "/article/appendixA"
        False -> ""
      }
    False -> "/article/chapter" <> ins(number + 1)
  }
  vxml
  |> prepend_link(next_link, "next-page")
  |> prepend_link(prev_link, "prev-page")
}

fn number_to_appendix_letter(number: Int) -> String {
  let ascii_code_for_a = 65
  let assert Ok(utf) = string.utf_codepoint(ascii_code_for_a - 1 + number)
  string.from_utf_codepoints([utf])
}

fn add_links_to_appendix(
  vxml: VXML,
  number: Int,
  num_appendices: Int,
  num_chapters: Int,
) -> VXML {
  let assert True = number >= 1 && number <= num_appendices
  let prev_link = case number == 1 {
    True ->
      case num_chapters > 0 {
        True -> "/article/chapter" <> ins(num_chapters)
        False -> "/"
      }
    False -> "/article/appendix" <> number_to_appendix_letter(number - 1)
  }
  let next_link = case number == num_appendices {
    True -> ""
    False -> "/article/appendix" <> number_to_appendix_letter(number + 1)
  }
  vxml
  |> prepend_link(next_link, "next-page")
  |> prepend_link(prev_link, "prev-page")
}

fn add_links_to_bootcamp(vxml: VXML, number: Int, num_bootcamps: Int) -> VXML {
  let assert True = number >= 1 && number <= num_bootcamps
  let prev_link = case number == num_bootcamps {
    True -> ""
    False -> "/article/bootcamp" <> ins(number + 1)
  }
  let next_link = case number == 1 {
    True -> "/"
    False -> "/article/bootcamp" <> ins(number - 1)
  }
  vxml
  |> prepend_link(next_link, "next-page")
  |> prepend_link(prev_link, "prev-page")
}

fn add_links_to_toc(vxml: VXML, num_bootcamps: Int, num_chapters: Int) -> VXML {
  let prev_link = case num_bootcamps > 0 {
    True -> "/article/bootcamp1"
    False -> ""
  }
  let next_link = case num_chapters > 0 {
    True -> "/article/chapter1"
    False -> ""
  }
  vxml
  |> prepend_link(next_link, "next-page")
  |> prepend_link(prev_link, "prev-page")
}

fn at_root(root: VXML) -> Result(VXML, DesugaringError) {
  let assert V(_, _, _, children) = root
  let chapters = core.v_children_with_tag(root, "Chapter")
  let bootcamps = core.v_children_with_tag(root, "Bootcamp")
  let appendices = core.v_children_with_tag(root, "Appendix")
  use toc <- on.empty_gt1_singleton(
    core.v_children_with_tag(root, "TOC"),
    on_empty: fn() { Error(DesugaringError(root.blame, "TOC missing")) },
    on_gt1: fn(_, _, _) { Error(DesugaringError(root.blame, "> 1 TOC")) },
  )
  let num_chapters = list.length(chapters)
  let num_bootcamps = list.length(bootcamps)
  let num_appendices = list.length(appendices)
  let chapters =
    list.index_map(chapters, fn(c, i) {
      add_links_to_chapter(c, i + 1, num_chapters, num_appendices)
    })
  let bootcamps =
    list.index_map(bootcamps, fn(c, i) {
      add_links_to_bootcamp(c, i + 1, num_bootcamps)
    })
  let appendices =
    list.index_map(appendices, fn(a, i) {
      add_links_to_appendix(a, i + 1, num_appendices, num_chapters)
    })
  let toc = add_links_to_toc(toc, num_bootcamps, num_chapters)
  let other_children =
    list.filter(children, fn(c) {
      !core.is_v_and_tag_is_one_of(c, ["TOC", "Chapter", "Bootcamp", "Appendix"])
    })
  Ok(
    V(
      ..root,
      children: list.flatten([
        other_children,
        [toc],
        chapters,
        bootcamps,
        appendices,
      ]),
    ),
  )
}

fn inner_param_to_transform(_: InnerParam) -> core.DesugarerTransform {
  at_root
  |> n2t.node_to_node_2_desugarer_transform_without_walking
}

type InnerParam =
  Nil

pub const name = "lbp_generate_prev_next_attributes"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
/// Adds previous and next navigation attributes to LBP
/// chapters, bootcamps, appendices, and the table of contents.
pub fn constructor() -> Desugarer {
  authoring.no_param_desugarer(
    name: name,
    transform: inner_param_to_transform(Nil),
  )
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
