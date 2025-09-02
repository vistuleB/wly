import on
import gleam/list
import gleam/option
import gleam/string.{inspect as ins}
import infrastructure.{type Desugarer, Desugarer, type DesugaringError, DesugaringError, type DesugaringWarning} as infra
import vxml.{type VXML, Attribute, V}
import nodemaps_2_desugarer_transforms as n2t

fn prepend_link(vxml: VXML, link_value: String, link_key: String) -> VXML {
  infra.v_prepend_attribute(vxml, Attribute(vxml.blame, link_key, link_value))
}

fn add_links_to_chapter(vxml: VXML, number: Int, num_chapters: Int) -> VXML {
  let assert True = number >= 1 && number <= num_chapters
  let prev_link = case number == 1 {
    True -> "/"
    False -> "/article/chapter" <> ins(number - 1)
  }
  let next_link = case number == num_chapters {
    True -> ""
    False -> "/article/chapter" <> ins(number + 1)
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

fn at_root(root: VXML) -> Result(#(VXML, List(DesugaringWarning)), DesugaringError) {
  let assert V(_, _, _, children) = root
  let chapters = infra.v_children_with_tag(root, "Chapter")
  let bootcamps = infra.v_children_with_tag(root, "Bootcamp")
  use toc <- on.empty_gt1_singleton(
    infra.v_children_with_tag(root, "TOC"),
    on_empty: Error(DesugaringError(root.blame, "TOC missing")),
    on_gt1: fn(_, _, _) {Error(DesugaringError(root.blame, "> 1 TOC"))},
  )
  let num_chapters = list.length(chapters)
  let num_bootcamps = list.length(bootcamps)
  let chapters = list.index_map(chapters, fn(c, i) {add_links_to_chapter(c, i + 1, num_chapters)})
  let bootcamps = list.index_map(bootcamps, fn(c, i) {add_links_to_bootcamp(c, i + 1, num_bootcamps)})
  let toc = add_links_to_toc(toc, num_bootcamps, num_chapters)
  let other_children = list.filter(children, fn(c) { !infra.is_v_and_tag_is_one_of(c, ["TOC", "Chapter", "Bootcamp"]) })
  V(..root, children: list.flatten([other_children, [toc], chapters, bootcamps]))
  |> n2t.add_no_warnings
  |> Ok
}

fn transform_factory(_: InnerParam) -> infra.DesugarerTransform {
  at_root
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(param)
}

type Param = Nil
type InnerParam = Nil

pub const name = "generate_lbp_prev_next_attributes"

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
  []
}

pub fn assertive_tests() {
  infra.assertive_test_collection_from_data_no_param(name, assertive_tests_data(), constructor)
}
