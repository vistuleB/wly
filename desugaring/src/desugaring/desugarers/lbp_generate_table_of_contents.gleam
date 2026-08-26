import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
}
import desugaring/nodemaps_2_transform as n2t
import gleam/list
import gleam/option.{type Option, Some}
import gleam/result
import gleam/string.{inspect as ins}
import on
import vxml.{type VXML, Attr, V}

pub const name = "lbp_generate_table_of_contents"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Generates the LBP table of contents using configured
/// container, heading, link, and optional spacer elements.
pub fn constructor(param: Param) -> Desugarer {
  authoring.desugarer_with_stringified_param(
    name: name,
    param: param,
    stringified_param: ins(param),
    prepare: param_to_inner_param,
    transform: inner_param_to_transform,
  )
}

type Param =
  #(
    // Table-of-contents element name.
    String,
    // Category-heading element name.
    String,
    // Individual chapter-link element name.
    String,
    // Optional spacer element between link groups.
    Option(String),
  )

type InnerParam =
  Param

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(param)
}

fn inner_param_to_transform(inner: InnerParam) -> core.DesugarerTransform {
  at_root(_, inner)
  |> n2t.node_to_node_2_desugarer_transform_without_walking
}

fn desugarer_blame(line_no: Int) {
  authoring.blame(name, line_no)
}

fn chapter_link(
  chapter_link_component_name: String,
  item: VXML,
  count: String,
) -> Result(VXML, DesugaringError) {
  let assert V(blame, tag, _, _) = item
  let tp = case tag {
    _ if tag == "Chapter" -> "chapter"
    _ if tag == "Bootcamp" -> "bootcamp"
    _ if tag == "Appendix" -> "appendix"
    _ -> panic as "expecting 'Chapter' or 'Bootcamp' or 'Appendix'"
  }
  use title_element <- on.ok(core.v_unique_child(item, "ArticleTitle"))
  let assert V(_, _, _, _) = title_element

  V(
    blame,
    chapter_link_component_name,
    [
      Attr(desugarer_blame(78), "article_type", count),
      Attr(desugarer_blame(79), "href", tp <> count),
    ],
    title_element.children,
  )
  |> Ok
}

fn type_of_chapters_title(
  type_of_chapters_title_component_name: String,
  label: String,
) -> VXML {
  V(
    desugarer_blame(91),
    type_of_chapters_title_component_name,
    [Attr(desugarer_blame(93), "label", label)],
    [],
  )
}

fn div_with_id_title_and_menu_items(
  type_of_chapters_title_component_name: String,
  id: String,
  title_label: String,
  menu_items: List(VXML),
) -> VXML {
  V(
    desugarer_blame(105),
    "div",
    [
      Attr(desugarer_blame(108), "id", id),
    ],
    [
      type_of_chapters_title(type_of_chapters_title_component_name, title_label),
      V(desugarer_blame(112), "ul", [], menu_items),
    ],
  )
}

type ArticalParams =
  #(String, String, String, CounterType)

type CounterType {
  Number
  Alphabetic
}

fn increamentor(index: Int, counter_type: CounterType) -> String {
  case counter_type {
    Number -> ins(index + 1)
    Alphabetic -> {
      let assert Ok(utf) = string.utf_codepoint(64 + index + 1)
      string.from_utf_codepoints([utf])
    }
  }
}

fn create_toc_child_div(
  article_params: ArticalParams,
  inner: InnerParam,
  children: List(VXML),
) -> Result(List(VXML), DesugaringError) {
  let #(tag_name, link, title, counter_type) = article_params
  let #(
    _,
    type_of_chapters_title_component_name,
    chapter_link_component_name,
    _,
  ) = inner

  use menu_items <- on.ok(
    children
    |> list.filter(core.is_v_and_tag_equals(_, tag_name))
    |> list.index_map(fn(chapter: VXML, index) {
      chapter_link(
        chapter_link_component_name,
        chapter,
        increamentor(index, counter_type),
      )
    })
    |> result.all,
  )

  let div =
    div_with_id_title_and_menu_items(
      type_of_chapters_title_component_name,
      link,
      title,
      menu_items,
    )

  on.false_true(
    list.is_empty(menu_items),
    on_false: fn() { Ok([div]) },
    on_true: fn() { Ok([]) },
  )
}

fn at_root(root: VXML, param: InnerParam) -> Result(VXML, DesugaringError) {
  let assert V(_, _, _, children) = root

  let #(toc_tag, _, _, maybe_spacer) = param

  let res =
    [
      #("Chapter", "chapter", "Chapters", Number),
      #("Bootcamp", "bootcamp", "Bootcamps", Number),
      #("Appendix", "appendix", "Appendices", Alphabetic),
    ]
    |> list.try_map(fn(a_params) {
      create_toc_child_div(a_params, param, children)
    })

  use merged <- on.ok(res)

  let flattened = list.flatten(merged)

  let toc_children = case maybe_spacer {
    Some(spacer_tag) -> {
      list.intersperse(flattened, V(desugarer_blame(197), spacer_tag, [], []))
    }
    _ -> flattened
  }

  let toc = V(desugarer_blame(202), toc_tag, [], toc_children)

  Ok(V(..root, children: [toc, ..children]))
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
