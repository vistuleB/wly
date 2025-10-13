import gleam/list
import gleam/option
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
import vxml.{type VXML, Attr, V}
import blame as bl
import on

fn prepand_0(number: String) {
  case string.length(number) {
    1 -> "0" <> number
    _ -> number
  }
}

fn chapter_link(
  chapter_link_component_name: String,
  item: VXML,
  _: Int,
) -> Result(VXML, DesugaringError) {
  let tp = "Chapter"

  let item_blame = item.blame

  use label_attr <- on.none_some(
    infra.v_first_attr_with_key(item, "title_gr"),
    on_none: Error(DesugaringError(
      item_blame,
      tp <> " missing title_gr attr",
    )),
  )

  use href_attr <- on.none_some(
    infra.v_first_attr_with_key(item, "title_en"),
    on_none: Error(DesugaringError(
      item_blame,
      tp <> " missing title_en attr",
    )),
  )

  use number_attr <- on.none_some(
    infra.v_first_attr_with_key(item, "number"),
    on_none: Error(DesugaringError(
      item_blame,
      tp <> " missing number attr",
    )),
  )

  let on_mobile_attr = case infra.v_first_attr_with_key(item, "on_mobile") {
    option.Some(attr) -> attr
    option.None -> label_attr
  }

  let link =
    number_attr.value
    |> string.split(".")
    |> list.map(prepand_0)
    |> string.join("-")
    <> "-"
    <> href_attr.value |> string.replace(" ", "-")

  Ok(
    V(
      item_blame,
      chapter_link_component_name,
      [
        Attr(label_attr.blame, "label", label_attr.value),
        Attr(on_mobile_attr.blame, "on_mobile", on_mobile_attr.value),
        Attr(
          number_attr.blame,
          "number",
          number_attr.value,
        ),
        Attr(desugarer_blame(82), "href", link),
      ],
      [],
    ),
  )
}

fn div_with_id_title_and_menu_items(id: String, menu_items: List(VXML)) -> VXML {
  V(desugarer_blame(90), "div", [Attr(desugarer_blame(90), "id", id)], [
    V(
      desugarer_blame(92),
      "ul",
      [Attr(desugarer_blame(94), "style", "list-style: none")],
      menu_items,
    ),
  ])
}

fn at_root(
  root: VXML,
  inner: InnerParam,
) -> Result(VXML, DesugaringError) {
  let assert V(_, _, _, children) = root
  let #(table_of_contents_tag, chapter_link_component_name) = inner
  let sections = infra.descendants_with_tag(root, "Section")
  use chapter_menu_items <- on.ok(
    sections
    |> list.index_map(fn(chapter: VXML, index) {
      chapter_link(chapter_link_component_name, chapter, index + 1)
    })
    |> result.all
  )
  let chapters_div =
    div_with_id_title_and_menu_items("Chapters", chapter_menu_items)
  let toc =
    V(desugarer_blame(117), table_of_contents_tag, [], [chapters_div])
  Ok(V(..root, children: [toc, ..children]))
}

fn transform_factory(inner: InnerParam) -> infra.DesugarerTransform {
  at_root(_, inner)
  |> n2t.at_root_2_desugarer_transform
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(param)
}

type Param = #(String,         String)
//             ↖               ↖
//             table of        chapter
//             contents tag    component name
type InnerParam = Param

pub const name = "generate_ii2_table_of_contents"
fn desugarer_blame(line_no: Int) { bl.Des([], name, line_no) }

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// generates table of contents for TI2 content with
/// sections
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
