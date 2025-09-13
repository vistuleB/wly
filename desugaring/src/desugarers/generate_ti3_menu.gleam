import blame as bl
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string.{inspect as ins}
import infrastructure.{
  type Desugarer,
  type DesugaringError,
  Desugarer,
} as infra
import vxml.{type VXML, type Attribute, Attribute, TextLine, V, T}
import nodemaps_2_desugarer_transforms as n2t
import on

fn an_attribute(key: String, value: String) -> Attribute {
  Attribute(desugarer_blame(15), key, value)
}

fn a_1_line_text_node(content: String) -> VXML {
  T(desugarer_blame(19), [TextLine(desugarer_blame(19), content)])
}

fn into_list(a: a) -> List(a) {
  [a]
}

type PageInfo = #(Int, Int)  // (chapter_no, sub_no)

type Menu {
  RightMenu
  LeftMenu
}

fn get_course_homepage(document: VXML) -> String {
  case infra.v_first_attribute_with_key(document, "course_homepage") {
    None -> ""
    Some(x) -> x.value
  }
}

fn format_chapter_link(chapter_no: Int, sub_no: Int) -> String {
  "./" <> ins(chapter_no) <> "-" <> ins(sub_no) <> ".html"
}

fn get_prev_next_info(
  current_chapter: Int,
  current_sub: Int,
  page_infos: List(PageInfo),
) -> #(Option(PageInfo), Option(PageInfo)) {
  let idx = infra.index_of(
    page_infos,
    #(current_chapter, current_sub),
  )
  use <- on.lazy_true_false(
    idx < 0,
    fn(){ panic as "#(current_chapter, current_sub) not found in page_infos" }
  )
  #(
    infra.get_at(page_infos, idx - 1) |> option.from_result,
    infra.get_at(page_infos, idx + 1) |> option.from_result,
  )
}

fn a_tag_with_href_and_content(
  href: String,
  content: String,
) -> VXML {
  V(
    desugarer_blame(68),
    "a",
    an_attribute("href", href) |> into_list,
    a_1_line_text_node(content) |> into_list,
  )
}

fn info_2_link(
  info: PageInfo,
  menu: Menu
) -> VXML {
  let href = format_chapter_link(info.0, info.1)

  let content = case info.1, menu {
      0, RightMenu -> "Kapitel " <> ins(info.0) <> "  " <> ">>"
      _, RightMenu -> "Kapitel " <> ins(info.0) <> "." <> ins(info.1) <> "  " <> ">>"
      0, LeftMenu -> "<<" <> " Kapitel " <> ins(info.0)
      _, LeftMenu -> "<<" <> " Kapitel " <> ins(info.0) <> "." <> ins(info.1)
    }

  let id_attribute = case menu {
    LeftMenu -> an_attribute("id", "prev-page")
    RightMenu -> an_attribute("id", "next-page")
  }

  a_tag_with_href_and_content(href, content)
  |> infra.v_prepend_attribute(id_attribute)
}

fn info_2_left_menu(
  prev_info: Option(PageInfo)
) -> VXML {
  let index_link =
    a_tag_with_href_and_content("./index.html", "Inhaltsverzeichnis")

  let index_link = case prev_info {
    None -> index_link |> infra.v_prepend_attribute(an_attribute("id", "prev-page"))
    Some(_) -> index_link
  }

  let ch_link_option = prev_info |> option.map(info_2_link(_, LeftMenu))

  V(
    desugarer_blame(111),
    "LeftMenu",
    an_attribute("class", "menu-left") |> into_list,
    option.values([
      Some(index_link),
      ch_link_option,
    ]),
  )
}

fn info_2_right_menu(
  prev_info: Option(PageInfo),
  homepage_url: String,
) -> VXML {
  let course_homepage_link =
    a_tag_with_href_and_content(homepage_url, "zür Kursübersicht")

  let ch_link_option = prev_info |> option.map(info_2_link(_, RightMenu))

  V(
    desugarer_blame(131),
    "RightMenu",
    an_attribute("class", "menu-right") |> into_list,
    option.values([
      Some(course_homepage_link),
      ch_link_option,
    ])
  )
}

fn infos_2_menu(
  prev_next_info: #(Option(PageInfo), Option(PageInfo)),
  homepage_url: String,
) -> VXML {
  V(
    desugarer_blame(146),
    "Menu",
    [],
    [
      info_2_left_menu(prev_next_info.0),
      info_2_right_menu(prev_next_info.1, homepage_url),
    ]
  )
}

fn prepend_menu_element(
  node: VXML,
  chapter_no: Int,
  sub_no: Int,
  page_infos: List(PageInfo),
  homepage_url: String,
) -> VXML {
  let menu = infos_2_menu(
    get_prev_next_info(chapter_no, sub_no, page_infos),
    homepage_url,
  )
  infra.v_prepend_child(node, menu)
}

fn prepend_menu_element_in_chapter_and_subchapters(
  chapter: VXML,
  chapter_no: Int,
  page_infos: List(PageInfo),
  homepage_url: String,
) -> VXML {
  let chapter =
    chapter
    |> prepend_menu_element(chapter_no, 0, page_infos, homepage_url)

  let assert V(_, _, _, children) = chapter

  let #(_, children) = list.map_fold(
    children,
    0,
    fn (acc, child) {
      case child {
        V(_, "Sub", _, _) -> #(
          acc + 1,
          prepend_menu_element(child, chapter_no, acc + 1, page_infos, homepage_url)
        )
        _ -> #(
          acc,
          child,
        )
      }
    }
  )

  V(..chapter, children: children)
}

fn collect_all_page_infos(root: VXML) -> List(PageInfo) {
  let chapters = infra.v_children_with_tag(root, "Chapter")
  list.index_fold(
    chapters,
    [],
    fn(acc, chapter, chapter_idx) {
      let chapter_no = chapter_idx + 1
      let subchapters = infra.v_children_with_tag(chapter, "Sub")
      let subchapters = list.index_map(
        subchapters,
        fn(_, sub_idx) { #(chapter_no, sub_idx + 1) }
      )
      list.flatten([acc, [#(chapter_no, 0)], subchapters])
    }
  )
}

fn at_root(root: VXML) -> Result(VXML, DesugaringError) {
  let assert V(_, "Document", _, children) = root
  let homepage_url = get_course_homepage(root)
  let page_infos = collect_all_page_infos(root)
  let #(_, children) = list.map_fold(
    children,
    0,
    fn (acc, child) {
      case child {
        V(_, tag, _, _) if tag == "Chapter" -> #(
          acc + 1,
          prepend_menu_element_in_chapter_and_subchapters(child, acc + 1, page_infos, homepage_url)
        )
        _ -> #(
          acc,
          child,
        )
      }
    }
  )
  Ok(V(..root, children: children))
}

fn transform_factory(_: InnerParam) -> infra.DesugarerTransform {
  at_root
  |> n2t.at_root_2_desugarer_transform
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(param)
}

type Param = Nil
type InnerParam = Nil

pub const name = "generate_ti3_menu"
fn desugarer_blame(line_no: Int) { bl.Des([], name, line_no) }

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// generate ti3 Menu navigation with left and right
/// menus containing previous/next chapter links,
/// index link, and course homepage link. The menu
/// is inserted after each Chapter and Sub element.
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
