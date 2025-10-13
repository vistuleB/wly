import blame as bl
import gleam/int
import gleam/list
import gleam/option
import gleam/pair
import gleam/result
import gleam/string.{inspect as ins}
import infrastructure.{
  type Desugarer,
  type DesugarerTransform,
  type DesugaringError,
  Desugarer,
  DesugaringError,
} as infra
import nodemaps_2_desugarer_transforms as n2t
import vxml.{type VXML, Attribute, Line, T, V}
import on

fn prepend_0(number: String) {
  case string.length(number) {
    1 -> "0" <> number
    _ -> number
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
    infra.v_first_attribute_with_key(item, "title_gr"),
    on_none: Error(DesugaringError(
      item_blame,
      tp <> " missing title_gr attribute",
    )),
  )

  use href_attr <- on.none_some(
    infra.v_first_attribute_with_key(item, "title_en"),
    on_none: Error(DesugaringError(
      item_blame,
      tp <> " missing title_en attribute",
    )),
  )

  use number_attribute <- on.none_some(
    infra.v_first_attribute_with_key(item, "number"),
    on_none: Error(DesugaringError(
      item_blame,
      tp <> " missing number attribute",
    )),
  )

  let link =
    "lecture-notes/"
    <> number_attribute.value
    |> string.split(".")
    |> list.map(prepend_0)
    |> string.join("-")
    <> "-"
    <> href_attr.value |> string.replace(" ", "-")
    <> ".html"

  // number span should always increament . for example we have sub-chapters 05-05-a and 05-05-b . so number span should be 5.5 and 5.6 for each
  let assert [chapter_number, ..] = number_attribute.value |> string.split(".")

  let number_span =
    V(item_blame, "span", [], [
      T(
        desugarer_blame(75),
        [
          Line(
            desugarer_blame(78),
            chapter_number <> "." <> ins(section_index) <> " - ",
          ),
        ]
      ),
    ])

  let a =
    V(
      item_blame,
      "a",
      [
        Attribute(desugarer_blame(90), "href", link)
      ],
      [
        T(item_blame, [Line(item_blame, label_attr.value)]),
      ]
    )

  let sub_chapter_number = ins(section_index)
  let margin_left =
    on.true_false(sub_chapter_number == "0", "0", fn() { "40px" })

  let style_attr =
    Attribute(desugarer_blame(102), "style", "margin-left: " <> margin_left)

  Ok(V(item_blame, chapter_link_component_name, [style_attr], [number_span, a]))
}

fn get_section_index(item: VXML, count: Int) -> Result(Int, DesugaringError) {
  let tp = "Chapter"

  use number_attribute <- on.none_some(
    infra.v_first_attribute_with_key(item, "number"),
    on_none: Error(DesugaringError(
      item.blame,
      tp <> " missing number attribute (b)",
    )),
  )

  let assert [section_number, ..] =
    number_attribute.value |> string.split(".") |> list.reverse()
  let assert Ok(section_number) = int.parse(section_number)

  case section_number == 0 {
    True -> Ok(0)
    False -> Ok(count + 1)
  }
}

fn div_with_id_title_and_menu_items(id: String, menu_items: List(VXML)) -> VXML {
  V(desugarer_blame(129), "div", [Attribute(desugarer_blame(129), "id", id)], [
    V(
      desugarer_blame(131),
      "ul",
      [Attribute(desugarer_blame(133), "style", "list-style: none")],
      menu_items,
    ),
  ])
}

fn at_root(
  root: VXML,
  inner: InnerParam,
) -> Result(VXML, DesugaringError) {
  let assert V(_, _, _, _) = root
  let #(toc_tag, chapter_link_component_name) = inner
  let sections = infra.descendants_with_tag(root, "section")
  use chapter_menu_items <- on.ok(
    sections
    |> list.map_fold(
      0, 
      fn(acc, chapter: VXML) {
        case get_section_index(chapter, acc) {
          Ok(section_index) -> #(
            section_index,
            chapter_link(chapter_link_component_name, chapter, section_index),
          )
          Error(error) -> #(acc, Error(error))
        }
      }
    )
    |> pair.second
    |> result.all
  )

  let chapters_div =
    div_with_id_title_and_menu_items("Chapters", chapter_menu_items)

  let toc =
    V(desugarer_blame(168), toc_tag, [], [chapters_div])

  infra.v_prepend_child(root, toc)
  |> Ok
}

fn transform_factory(inner: InnerParam) -> infra.DesugarerTransform {
  at_root(_, inner)
  |> n2t.at_root_2_desugarer_transform
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(param)
}

type Param = #(String,              String)
//             ↖                    ↖
//             tag name for         tag name for
//             table of contents    individual chapter links
type InnerParam = Param

pub const name = "generate_zi2_table_of_contents_html"
fn desugarer_blame(line_no: Int) { bl.Des([], name, line_no) }

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// generates HTML table of contents for TI2 content
/// with sections
pub fn constructor(param: Param) -> Desugarer {
  Desugarer(
    name: name,
    stringified_param: option.Some(ins(param)),
    stringified_outside: option.None,
    transform: case param_to_inner_param(param) {
      Error(error) -> fn(_) { Error(error) }
      Ok(inner) -> transform_factory(inner)
    },
  )
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
fn assertive_tests_data() -> List(infra.AssertiveTestData(Param)) {
  []
}

pub fn assertive_tests() {
  infra.assertive_test_collection_from_data(name, assertive_tests_data(), constructor)
}
