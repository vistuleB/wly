import blame as bl
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string.{inspect as ins}
import infrastructure.{
  type Desugarer,
  type DesugaringError,
  Desugarer,
} as infra
import vxml.{
  type VXML,
  type Attribute,
  Attribute,
  TextLine,
  V,
  T,
}
import nodemaps_2_desugarer_transforms as n2t
import on

type PageInfo = #(Int, Int)  // (chapter_no, sub_no)

type PrevOrNext {
  Prev
  Next
}

const b = bl.Des([], name, 14)

const id_prev_page_attribute = Attribute(b, "id", "prev-page")

const id_next_page_attribute = Attribute(b, "id", "next-page")

const index_link = V(
  b,
  "a",
  [Attribute(b, "href", "./index.html")],
  [T(b, [TextLine(b, "Inhaltsverzeichnis")])],
)

fn an_attribute(key: String, value: String) -> Attribute {
  Attribute(desugarer_blame(42), key, value)
}

fn a_1_line_text_node(content: String) -> VXML {
  T(desugarer_blame(46), [TextLine(desugarer_blame(46), content)])
}

fn into_list(a: a) -> List(a) {
  [a]
}

fn homepage_link(homepage_url: String) -> VXML {
  V(
    b,
    "a",
    an_attribute("href", homepage_url) |> into_list,
    a_1_line_text_node("zür Kursübersicht") |> into_list,
  )
}

fn page_info_2_href(info: PageInfo) -> String {
  "./" <> ins(info.0) <> "-" <> ins(info.1) <> ".html"
}

fn page_info_2_link(
  info: PageInfo,
  prev_or_next: PrevOrNext,
) -> VXML {
  let id_attribute = case prev_or_next {
    Prev -> id_prev_page_attribute
    Next -> id_next_page_attribute
  }

  let href_attribute = 
    info
    |> page_info_2_href
    |> an_attribute("href", _)

  let content_text_node = case info.1, prev_or_next {
    0, Prev -> "<<" <> " Kapitel " <> ins(info.0)
    _, Prev -> "<<" <> " Kapitel " <> ins(info.0) <> "." <> ins(info.1)
    0, Next -> "Kapitel " <> ins(info.0) <> "  " <> ">>"
    _, Next -> "Kapitel " <> ins(info.0) <> "." <> ins(info.1) <> "  " <> ">>"
  }
  |> a_1_line_text_node

  V(
    desugarer_blame(89),
    "a",
    [
      id_attribute,
      href_attribute,
    ],
    [
      content_text_node,
    ],
  )
}

fn links_2_left_menu(
  links: #(VXML, VXML, Option(VXML), Option(VXML))
) -> VXML {
  V(
    desugarer_blame(105),
    "LeftMenu",
    an_attribute("class", "menu-left") |> into_list,
    option.values([Some(links.0), links.2]),
  )
}

fn links_2_right_menu(
  links: #(VXML, VXML, Option(VXML), Option(VXML))
) -> VXML {
  V(
    desugarer_blame(116),
    "RightMenu",
    an_attribute("class", "menu-right") |> into_list,
    option.values([Some(links.1), links.3]),
  )
}

fn infos_2_4_links(
  prev_next_info: #(Option(PageInfo), Option(PageInfo)),
  homepage_url: String,
) -> #(VXML, VXML, Option(VXML), Option(VXML)) {
  #(
    index_link,
    homepage_link(homepage_url),
    prev_next_info.0 |> option.map(page_info_2_link(_, Prev)),
    prev_next_info.1 |> option.map(page_info_2_link(_, Next)),
  )
}

fn links_2_menu(
  links: #(VXML, VXML, Option(VXML), Option(VXML))
) -> VXML {
  V(
    desugarer_blame(139),
    "Menu",
    [],
    [
      links_2_left_menu(links),
      links_2_right_menu(links),
    ]
  )
}

fn infos_2_menu(
  prev_next_info: #(Option(PageInfo), Option(PageInfo)),
  homepage_url: String,
) -> VXML {
  infos_2_4_links(prev_next_info, homepage_url)
  |> links_2_menu
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

fn process_chapter(
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
          child
          |> prepend_menu_element(chapter_no, acc + 1, page_infos, homepage_url)
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

fn get_course_homepage(document: VXML) -> String {
  case infra.v_first_attribute_with_key(document, "course_homepage") {
    None -> ""
    Some(x) -> x.value
  }
}

fn generate_page_infos(root: VXML) -> List(PageInfo) {
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
  let page_infos = generate_page_infos(root)
  let #(_, children) = list.map_fold(
    children,
    0,
    fn (acc, child) {
      case child {
        V(_, "Chapter", _, _) -> #(
          acc + 1,
          process_chapter(child, acc + 1, page_infos, homepage_url)
        )
        _ -> #(acc, child)
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

pub const name = "ti2_create_menu"
fn desugarer_blame(line_no: Int) { bl.Des([], name, line_no) }

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// generate ti2 Menu navigation with left and right
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
  [
    infra.AssertiveTestDataNoParam(
      source:   "
                  <> Document
                    course_homepage=https://example.com/cs101
                    <> Chapter
                      <> Sub
                        <>
                          \"Sub content 1.1\"
                      <> Sub
                        <>
                          \"Sub content 1.2\"
                    <> Chapter
                      <>
                        \"Chapter 2 content\"
                ",
      expected: "
                  <> Document
                    course_homepage=https://example.com/cs101
                    <> Chapter
                      <> Menu
                        <> LeftMenu
                          class=menu-left
                          <> a
                            href=./index.html
                            <>
                              \"Inhaltsverzeichnis\"
                        <> RightMenu
                          class=menu-right
                          <> a
                            href=https://example.com/cs101
                            <>
                              \"zür Kursübersicht\"
                          <> a
                            id=next-page
                            href=./1-1.html
                            <>
                              \"Kapitel 1.1  >>\"
                      <> Sub
                        <> Menu
                          <> LeftMenu
                            class=menu-left
                            <> a
                              href=./index.html
                              <>
                                \"Inhaltsverzeichnis\"
                            <> a
                              id=prev-page
                              href=./1-0.html
                              <>
                                \"<< Kapitel 1\"
                          <> RightMenu
                            class=menu-right
                            <> a
                              href=https://example.com/cs101
                              <>
                                \"zür Kursübersicht\"
                            <> a
                              id=next-page
                              href=./1-2.html
                              <>
                                \"Kapitel 1.2  >>\"
                        <>
                          \"Sub content 1.1\"
                      <> Sub
                        <> Menu
                          <> LeftMenu
                            class=menu-left
                            <> a
                              href=./index.html
                              <>
                                \"Inhaltsverzeichnis\"
                            <> a
                              id=prev-page
                              href=./1-1.html
                              <>
                                \"<< Kapitel 1.1\"
                          <> RightMenu
                            class=menu-right
                            <> a
                              href=https://example.com/cs101
                              <>
                                \"zür Kursübersicht\"
                            <> a
                              id=next-page
                              href=./2-0.html
                              <>
                                \"Kapitel 2  >>\"
                        <>
                          \"Sub content 1.2\"
                    <> Chapter
                      <> Menu
                        <> LeftMenu
                          class=menu-left
                          <> a
                            href=./index.html
                            <>
                              \"Inhaltsverzeichnis\"
                          <> a
                            id=prev-page
                            href=./1-2.html
                            <>
                              \"<< Kapitel 1.2\"
                        <> RightMenu
                          class=menu-right
                          <> a
                            href=https://example.com/cs101
                            <>
                              \"zür Kursübersicht\"
                      <>
                        \"Chapter 2 content\"
                ",
    ),
  ]
}

pub fn assertive_tests() {
  infra.assertive_test_collection_from_data_no_param(name, assertive_tests_data(), constructor)
}
