import gleam/list
import gleam/option.{Some,None}
import gleam/result
import gleam/string.{inspect as ins}
import gleam/regexp
import infrastructure.{
  type Desugarer,
  type DesugaringError,
  Desugarer,
  DesugaringError,
} as infra
import vxml.{type VXML, type TextLine, Attribute, TextLine, V, T}
import nodemaps_2_desugarer_transforms as n2t
import blame as bl
import on

type ChapterNo = Int
type SubChapterNo = Int
type TitleElements = List(VXML)
type ChapterTitle = List(VXML)
type SubchapterTitle = List(VXML)

fn format_chapter_link(chapter_no: Int, sub_no: Int) -> String {
  "./" <> ins(chapter_no) <> "-" <> ins(sub_no) <> ".html"
}

fn extract_title(chapter_or_subchapter ch: VXML, title_tag t: String) -> Result(TitleElements, DesugaringError) {
  use title_element <- on.error_ok(
    infra.v_unique_child_with_tag(ch, t),
    fn(e) {
      case e {
        infra.MoreThanOne -> Error(DesugaringError(infra.v_blame(ch), "more than one '" <> t <> "' element"))
        infra.LessThanOne -> Error(DesugaringError(infra.v_blame(ch), "did not find '" <> t <> "' element"))
      }
    }
  )
  let assert V(_, _, _, children) = title_element
  let assert [T(blame, contents), ..rest] = children
  let assert Ok(re) = regexp.from_string("^(\\d+)(\\.(\\d+)?)?\\s")
  let without_number =
    contents
    |> list.map(fn(line: TextLine) { line.content })
    |> string.join("")
    |> regexp.replace(re, _, "")
  Ok([T(blame, [TextLine(blame, without_number)]), ..rest])
}

fn chapters_number_title(root: VXML) -> Result(List(#(VXML, ChapterNo, ChapterTitle)), DesugaringError) {
  root
  |> infra.v_index_children_with_tag("Chapter")
  |> list.try_map(
    fn(tup: #(VXML, Int)) {
      use title <- on.ok(extract_title(tup.0, "ChapterTitle"))
      Ok(#(tup.0, tup.1 + 1, title))
  })
}

fn extract_subchapter_titles(chapter: VXML) -> Result(List(#(SubChapterNo, SubchapterTitle)), DesugaringError) {
  chapter
  |> infra.v_index_children_with_tag("Sub")
  |> list.try_map(
    fn(sub: #(VXML, Int)) {
      use subchapter_title <- on.ok(extract_title(sub.0, "SubTitle"))
      Ok(#(sub.1 + 1, subchapter_title))
  })
}

fn all_subchapters(
  chapters: List(#(VXML, ChapterNo, ChapterTitle))
) -> Result(
  List(#(ChapterNo, ChapterTitle, List(#(SubChapterNo, SubchapterTitle)))),
  DesugaringError,
) {
  chapters
  |> list.try_map(
    fn(chapter: #(VXML, Int, SubchapterTitle)) {
      use subchapter_titles <- on.ok(chapter.0 |> extract_subchapter_titles)
      Ok(#(chapter.1, chapter.2, subchapter_titles))
  })
}

fn construct_subchapter_item(subchapter_title: SubchapterTitle, subchapter_number: Int, chapter_number: Int) -> VXML {
  let blame = desugarer_blame(83)
  V(
    blame,
    "li",
    [],
    [
      T(blame, [TextLine(blame, ins(chapter_number) <> "." <> ins(subchapter_number) <> " - ")]),
      V(
        blame,
        "a",
        [Attribute(blame, "href", format_chapter_link(chapter_number, subchapter_number))],
        subchapter_title,
      )
    ]
  )
}

fn construct_chapter_item(chapter_number: Int, chapter_title: ChapterTitle, subchapters: List(#(SubChapterNo, SubchapterTitle))) -> VXML {
  let blame = desugarer_blame(101)
  let subchapters_ol = case subchapters {
    [] -> []
    _ -> [
      V(
        blame,
        "ol",
        [Attribute(blame, "class", "index__list__subchapter")],
        list.map(
          subchapters,
          fn(subchapter) {
            let #(subchapter_number, subchapter_title) = subchapter
            construct_subchapter_item(subchapter_title, subchapter_number, chapter_number)
          }
        )
      )
    ]
  }

  V(
    blame,
    "li",
    [Attribute(blame, "class", "index__list__chapter")],
    list.flatten([
      [
        T(blame, [TextLine(blame, ins(chapter_number) <> " - ")]),
        V(
          blame,
          "a",
          [Attribute(blame, "href", "./" <> ins(chapter_number) <> "-0" <> ".html")],
          chapter_title,
        )
      ],
      subchapters_ol
    ])
  )
}

fn construct_header(document: VXML) -> VXML {
  let blame = desugarer_blame(140)

  let title =
    case infra.v_first_attribute_with_key(document, "title") {
      None -> "no title"
      Some(x) -> x.value
    }

  let program =
    case infra.v_first_attribute_with_key(document, "program") {
      None -> "no program"
      Some(x) -> x.value
    }

  let institution =
    case infra.v_first_attribute_with_key(document, "institution") {
      None -> "no institution"
      Some(x) -> x.value
    }

  let lecturer =
    case infra.v_first_attribute_with_key(document, "lecturer") {
      None -> "no lecturer"
      Some(x) -> x.value
    }

  V(
    blame,
    "header",
    [Attribute(blame, "class", "index__header")],
    [
      V(
        blame,
        "h1",
        [Attribute(blame, "class", "index__header__title")],
        [T(blame, [TextLine(blame, title)])]
      ),
      V(
        blame,
        "span",
        [Attribute(blame, "class", "index__header__subtitle")],
        [T(blame, [TextLine(blame, program)])]
      ),
      V(
        blame,
        "span",
        [Attribute(blame, "class", "index__header__subtitle")],
        [T(blame, [TextLine(blame, lecturer <> ", " <> institution)])]
      )
    ]
  )
}

fn construct_right_menu(document: VXML) -> VXML {
  let blame = desugarer_blame(194)

  let first_chapter_title =
    document
    |> infra.v_children_with_tag("Chapter")
    |> list.first
    |> result.map(fn(chapter) { infra.v_first_attribute_with_key(chapter, "title") })
    |> result.map(fn(opt) { option.map(opt, fn(attr) {attr.value})})
    |> result.map(fn(opt) { option.unwrap(opt, "no title found")})
    |> result.unwrap("no title found")

    V(
      blame,
      "RightMenu",
      [Attribute(blame, "class", "menu-right")],
      [ V(
          blame,
          "a",
          [
            Attribute(blame, "id", "next-page"),
            Attribute(blame, "href", format_chapter_link(1, 0)),
          ],
          [
            T(blame, [TextLine(blame, "1. " <> first_chapter_title <> " >>")]),
          ]
        )
      ]
    )
}

fn construct_menu(document: VXML) -> VXML {
  let blame = desugarer_blame(225)

  let course_homepage_link =
    case infra.v_first_attribute_with_key(document, "course_homepage") {
      None -> "no url for course homepage"
      Some(x) -> x.value
    }

  let menu_left =
    V(
      blame,
      "LeftMenu",
      [Attribute(blame, "class", "menu-left")]
      ,[
        V(blame, "a", [Attribute(blame, "href", course_homepage_link)], [T(blame, [TextLine(blame, "zür Kursübersicht")])])
      ]
    )

  V(
    blame,
    "nav",
    [ Attribute(blame, "class", "menu")],
    [ menu_left,
      construct_right_menu(document)
    ]
  )
}

fn construct_index(chapters: List(#(ChapterNo, ChapterTitle, List(#(SubChapterNo, SubchapterTitle))))) -> VXML {
  let blame = desugarer_blame(254)

  V(
    blame,
    "section",
    [],
    [
      V(
        blame,
        "ol",
        [Attribute(blame, "class", "index__list")],
        list.map(chapters, fn(chapter) {
          let #(chapter_number, chapter_title, subchapters) = chapter
          construct_chapter_item(chapter_number, chapter_title, subchapters)
        })
      )
    ]
  )
}

fn at_root(root: VXML) -> Result(VXML, DesugaringError) {
  let assert V(_, "Document", _, children) = root
  let menu_node = construct_menu(root)
  let header_node = construct_header(root)
  use chapters <- on.ok(chapters_number_title(root))
  use subchapters <- on.ok(all_subchapters(chapters))
  let index_list_node = construct_index(subchapters)
  let index_node = V(
    desugarer_blame(282),
    "Index",
    [Attribute(desugarer_blame(284), "path", "./index.html")],
    [menu_node, header_node, index_list_node]
  )
  Ok(V(..root, children: [index_node, ..children]))
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

pub const name = "generate_ti3_index"
fn desugarer_blame(line_no: Int) { bl.Des([], name, line_no) }

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// Generate ti3 Index element
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
                    title=Introduction to Computer Science
                    program=Computer Science
                    institution=University of Example
                    lecturer=Dr. Smith
                    course_homepage=https://example.com/cs101
                    <> Chapter
                      title=1. Introduction
                      <> ChapterTitle
                        <>
                          \"1. Introduction\"
                      <> Sub
                        <> SubTitle
                          <>
                            \"1.1 Overview\"
                      <> Sub
                        <> SubTitle
                          <>
                            \"1.2 Goals\"
                    <> Chapter
                      title=2. Fundamentals
                      <> ChapterTitle
                        <>
                          \"2. Fundamentals\"
                      <> Sub
                        <> SubTitle
                          <>
                            \"2.1 Basic Concepts\"
                ",
      expected: "
                  <> Document
                    title=Introduction to Computer Science
                    program=Computer Science
                    institution=University of Example
                    lecturer=Dr. Smith
                    course_homepage=https://example.com/cs101
                    <> Index
                      path=./index.html
                      <> nav
                        class=menu
                        <> LeftMenu
                          class=menu-left
                          <> a
                            href=https://example.com/cs101
                            <>
                              \"zür Kursübersicht\"
                        <> RightMenu
                          class=menu-right
                          <> a
                            id=next-page
                            href=./1-0.html
                            <>
                              \"1. 1. Introduction >>\"
                      <> header
                        class=index__header
                        <> h1
                          class=index__header__title
                          <>
                            \"Introduction to Computer Science\"
                        <> span
                          class=index__header__subtitle
                          <>
                            \"Computer Science\"
                        <> span
                          class=index__header__subtitle
                          <>
                            \"Dr. Smith, University of Example\"
                      <> section
                        <> ol
                          class=index__list
                          <> li
                            class=index__list__chapter
                            <>
                              \"1 - \"
                            <> a
                              href=./1-0.html
                              <>
                                \"Introduction\"
                            <> ol
                              class=index__list__subchapter
                              <> li
                                <>
                                  \"1.1 - \"
                                <> a
                                  href=./1-1.html
                                  <>
                                    \"Overview\"
                              <> li
                                <>
                                  \"1.2 - \"
                                <> a
                                  href=./1-2.html
                                  <>
                                    \"Goals\"
                          <> li
                            class=index__list__chapter
                            <>
                              \"2 - \"
                            <> a
                              href=./2-0.html
                              <>
                                \"Fundamentals\"
                            <> ol
                              class=index__list__subchapter
                              <> li
                                <>
                                  \"2.1 - \"
                                <> a
                                  href=./2-1.html
                                  <>
                                    \"Basic Concepts\"
                    <> Chapter
                      title=1. Introduction
                      <> ChapterTitle
                        <>
                          \"1. Introduction\"
                      <> Sub
                        <> SubTitle
                          <>
                            \"1.1 Overview\"
                      <> Sub
                        <> SubTitle
                          <>
                            \"1.2 Goals\"
                    <> Chapter
                      title=2. Fundamentals
                      <> ChapterTitle
                        <>
                          \"2. Fundamentals\"
                      <> Sub
                        <> SubTitle
                          <>
                            \"2.1 Basic Concepts\"
                ",
    ),
  ]
}

pub fn assertive_tests() {
  infra.assertive_test_collection_from_data_no_param(name, assertive_tests_data(), constructor)
}
