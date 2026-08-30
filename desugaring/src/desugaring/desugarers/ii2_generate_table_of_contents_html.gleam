import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError, DesugaringError,
}
import desugaring/nodemaps_2_transform as n2t
import gleam/int
import gleam/list
import gleam/pair
import gleam/result
import gleam/string.{inspect as ins}
import on
import vxml.{type VXML, Attr, Line, T, V}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(param)
}

fn inner_param_to_transform(inner: InnerParam) -> core.DesugarerTransform {
  at_root(_, inner)
  |> n2t.node_to_node_2_desugarer_transform_without_walking
}

fn at_root(root: VXML, inner: InnerParam) -> Result(VXML, DesugaringError) {
  let assert V(_, _, _, _) = root
  let #(toc_tag, chapter_link_component_name) = inner
  let sections = core.descendants_with_tag(root, "section")
  use chapter_menu_items <- on.ok(
    sections
    |> list.map_fold(0, fn(acc, chapter: VXML) {
      case get_section_index(chapter, acc) {
        Ok(section_index) -> #(
          section_index,
          chapter_link(chapter_link_component_name, chapter, section_index),
        )
        Error(error) -> #(acc, Error(error))
      }
    })
    |> pair.second
    |> result.all,
  )

  let chapters_div =
    div_with_id_title_and_menu_items("Chapters", chapter_menu_items)

  let toc = V(desugarer_blame(147), toc_tag, [], [chapters_div])

  core.v_prepend_child(root, toc)
  |> Ok
}

fn get_section_index(item: VXML, count: Int) -> Result(Int, DesugaringError) {
  let tp = "Chapter"

  use number_attr <- on.none_some(
    core.v_first_attr_with_key(item, "number"),
    on_none: fn() {
      Error(DesugaringError(item.blame, tp <> " missing number attr (b)"))
    },
  )

  let assert [section_number, ..] =
    number_attr.val |> string.split(".") |> list.reverse()
  let assert Ok(section_number) = int.parse(section_number)

  case section_number == 0 {
    True -> Ok(0)
    False -> Ok(count + 1)
  }
}

fn chapter_link(
  chapter_link_component_name: String,
  item: VXML,
  section_index: Int,
) -> Result(VXML, DesugaringError) {
  let tp = "Chapter"

  let item_blame = item.blame

  use label_attr <- on.none_some(
    core.v_first_attr_with_key(item, "title_gr"),
    on_none: fn() {
      Error(DesugaringError(item_blame, tp <> " missing title_gr attr"))
    },
  )

  use href_attr <- on.none_some(
    core.v_first_attr_with_key(item, "title_en"),
    on_none: fn() {
      Error(DesugaringError(item_blame, tp <> " missing title_en attr"))
    },
  )

  use number_attr <- on.none_some(
    core.v_first_attr_with_key(item, "number"),
    on_none: fn() {
      Error(DesugaringError(item_blame, tp <> " missing number attr"))
    },
  )

  let link =
    "lecture-notes/"
    <> number_attr.val
    |> string.split(".")
    |> list.map(prepend_0)
    |> string.join("-")
    <> "-"
    <> href_attr.val |> string.replace(" ", "-")
    <> ".html"

  // number span should always increament . for example we have sub-chapters 05-05-a and 05-05-b . so number span should be 5.5 and 5.6 for each
  let assert [chapter_number, ..] = number_attr.val |> string.split(".")

  let number_span =
    V(item_blame, "span", [], [
      T(desugarer_blame(66), [
        Line(
          desugarer_blame(68),
          chapter_number <> "." <> ins(section_index) <> " - ",
        ),
      ]),
    ])

  let a =
    V(item_blame, "a", [Attr(desugarer_blame(75), "href", link)], [
      T(item_blame, [Line(item_blame, label_attr.val)]),
    ])

  let sub_chapter_number = ins(section_index)
  let margin_left = case sub_chapter_number {
    "0" -> "0"
    _ -> "40px"
  }

  let style_attr =
    Attr(desugarer_blame(86), "style", "margin-left: " <> margin_left)

  Ok(V(item_blame, chapter_link_component_name, [style_attr], [number_span, a]))
}

fn desugarer_blame(line_no: Int) {
  authoring.blame(name, line_no)
}

fn div_with_id_title_and_menu_items(
  id: String,
  menu_items: List(VXML),
) -> VXML {
  V(desugarer_blame(115), "div", [Attr(desugarer_blame(115), "id", id)], [
    V(
      desugarer_blame(117),
      "ul",
      [Attr(desugarer_blame(119), "style", "list-style: none")],
      menu_items,
    ),
  ])
}

type Param =
  #(
    // Element name for the table of contents.
    String,
    // Element name for individual chapter links.
    String,
  )

type InnerParam =
  Param

pub const name = "ii2_generate_table_of_contents_html"

fn prepend_0(number: String) {
  case string.length(number) {
    1 -> "0" <> number
    _ -> number
  }
}

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
/// Generates an HTML table of contents for II2 chapters
/// using the configured container and link element names.
pub fn constructor(param: Param) -> Desugarer {
  authoring.desugarer(
    name: name,
    param: param,
    prepare: param_to_inner_param,
    transform: inner_param_to_transform,
  )
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
fn assertive_tests_data() -> List(core.AssertiveTestData(Param)) {
  []
}

pub fn assertive_tests() {
  core.assertive_test_collection_from_data(
    name,
    assertive_tests_data(),
    constructor,
  )
}
