import gleam/list
import gleam/option.{type Option, Some}
import gleam/result
import gleam/string.{inspect as ins}
import infrastructure.{
  type Desugarer,
  type DesugarerTransform,
  type DesugaringError,
  Desugarer,
} as infra
import vxml.{type VXML, Attr, V}
import blame as bl
import nodemaps_2_desugarer_transforms as n2t
import on

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
  use title_element <- on.ok(infra.v_unique_child(item, "ArticleTitle"))
  let assert V(_, _, _, _) = title_element

  V(
    blame,
    chapter_link_component_name,
    [
      Attr(desugarer_blame(35), "article_type", count),
      Attr(desugarer_blame(36), "href", tp <> count),
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
    desugarer_blame(48),
    type_of_chapters_title_component_name,
    [Attr(desugarer_blame(50), "label", label)],
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
    desugarer_blame(62),
    "div",
    [
      Attr(desugarer_blame(65), "id", id),
    ],
    [
      type_of_chapters_title(type_of_chapters_title_component_name, title_label),
      V(desugarer_blame(69), "ul", [], menu_items),
    ],
  )
}

type ArticalParams = #(String, String, String, CounterType)

type CounterType {
  Number
  Alphabetic
}

fn increamentor(index: Int, counter_type: CounterType) -> String {
  case counter_type {
    Number -> ins(index + 1) 
    Alphabetic ->{
      let assert Ok(utf) = string.utf_codepoint(64 + index + 1)
      string.from_utf_codepoints([utf])
    }
  }
}


fn create_toc_child_div(article_params: ArticalParams, inner: InnerParam, children: List(VXML)) -> Result(List(VXML), DesugaringError) {
  let #(tag_name, link, title, counter_type) = article_params
  let #(
    _,
    type_of_chapters_title_component_name,
    chapter_link_component_name,
    _,
  ) = inner

  use menu_items <- on.ok(
    children
    |> list.filter(infra.is_v_and_tag_equals(_, tag_name))
    |> list.index_map(fn(chapter: VXML, index) { chapter_link(chapter_link_component_name, chapter, increamentor(index, counter_type)) })
    |> result.all
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
    on_true: fn() { Ok([]) }
  )
}

fn at_root(root: VXML, param: InnerParam) -> Result(VXML, DesugaringError) {
  let assert V(_, _, _, children) = root

  let #(
    toc_tag,
    _,
    _,
    maybe_spacer,
  ) = param

  let res = [
    #("Chapter", "chapter", "Chapters", Number),
    #("Bootcamp", "bootcamp", "Bootcamps", Number),
    #("Appendix", "appendix", "Appendices", Alphabetic),
  ] |> list.try_map(fn(a_params) { create_toc_child_div(a_params, param, children) })
   
  use merged <- on.ok(res)

  let flattened = list.flatten(merged)

  let toc_children = case maybe_spacer {
    Some(spacer_tag) -> { list.intersperse(flattened, V(desugarer_blame(144), spacer_tag, [], [])) }
    _ -> flattened
  }

  let toc = V(desugarer_blame(148), toc_tag, [], toc_children)

  Ok(V(..root, children: [toc, ..children]))
}

fn desugarer_factory(inner: InnerParam) -> infra.DesugarerTransform {
  at_root(_, inner)
  |> n2t.at_root_2_desugarer_transform
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(param)
}

type Param = #(String,   String,                String,        Option(String))
//             ↖         ↖                      ↖              ↖
//             tag name  tag name               tag name       optional tag name
//             table of  of 'big title'         individual     for spacer between
//             contents  (Chapters, Bootcamps)  chapter links  two groups of chapter links
type InnerParam = Param

pub const name = "generate_lbp_table_of_contents"
fn desugarer_blame(line_no: Int) { bl.Des([], name, line_no) }

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// generates the LBP table of contents while
/// admitting custom values for the root tag name
/// of the table of contents, as well as for the tag
/// name of the chapter (& bootcamp) links and the
/// tag name for the Chapter/Bootcamp category
/// banners, and an optional spacer tag name for an
/// element to be placed between the two categories
pub fn constructor(param: Param) -> Desugarer {
  Desugarer(
    name: name,
    stringified_param: option.None,
    stringified_outside: option.None,
    transform: case param_to_inner_param(param) {
      Error(error) -> fn(_) { Error(error) }
      Ok(inner) -> desugarer_factory(inner)
    }
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
