import gleam/list
import gleam/option
import gleam/result
import gleam/string.{inspect as ins}
import infrastructure.{type Desugarer, Desugarer, type DesugarerTransform, type DesugaringError, type DesugaringWarning, DesugaringError} as infra
import nodemaps_2_desugarer_transforms as n2t
import vxml.{type VXML, Attribute, V}
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
    infra.v_first_attribute_with_key(item, "title_gr"),
    on_none: Error(DesugaringError(
      item_blame,
      "(generate_ti2_table_of_contents)" <> tp <> " missing title_gr attribute",
    )),
  )

  use href_attr <- on.none_some(
    infra.v_first_attribute_with_key(item, "title_en"),
    on_none: Error(DesugaringError(
      item_blame,
      "(generate_ti2_table_of_contents)" <> tp <> " missing title_en attribute",
    )),
  )

  use number_attribute <- on.none_some(
    infra.v_first_attribute_with_key(item, "number"),
    on_none: Error(DesugaringError(
      item_blame,
      "(generate_ti2_table_of_contents)" <> tp <> " missing number attribute",
    )),
  )

  let on_mobile_attr = case infra.v_first_attribute_with_key(item, "on_mobile") {
    option.Some(attr) -> attr
    option.None -> label_attr
  }

  let link =
    number_attribute.value
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
        Attribute(label_attr.blame, "label", label_attr.value),
        Attribute(on_mobile_attr.blame, "on_mobile", on_mobile_attr.value),
        Attribute(
          number_attribute.blame,
          "number",
          number_attribute.value,
        ),
        Attribute(desugarer_blame(76), "href", link),
      ],
      [],
    ),
  )
}

fn div_with_id_title_and_menu_items(id: String, menu_items: List(VXML)) -> VXML {
  V(desugarer_blame(84), "div", [Attribute(desugarer_blame(84), "id", id)], [
    V(
      desugarer_blame(86),
      "ul",
      [Attribute(desugarer_blame(88), "style", "list-style: none")],
      menu_items,
    ),
  ])
}

fn at_root(
  root: VXML,
  inner: InnerParam,
) -> Result(#(VXML, List(DesugaringWarning)), DesugaringError) {
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

  infra.v_prepend_child(
    root,
    V(desugarer_blame(114), table_of_contents_tag, [], [chapters_div]),
  )
  |> n2t.add_no_warnings
  |> Ok
}

fn transform_factory(inner: InnerParam) -> infra.DesugarerTransform {
  at_root(_, inner)
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(param)
}

type Param = #(String,         String)
//             ↖               ↖
//             table of        chapter
//             contents tag    component name
type InnerParam = Param

pub const name = "generate_ti2_table_of_contents"
fn desugarer_blame(line_no: Int) {bl.Des([], name, line_no)}

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
