import gleam/list
import gleam/option.{Some,None}
import gleam/result
import gleam/string.{inspect as ins}
import gleam/regexp
import infrastructure.{
  type Desugarer,
  type DesugaringError,
  Desugarer,
} as infra
import vxml.{
  type VXML,
  type TextLine,
  Attribute,
  TextLine,
  V,
  T,
}
import nodemaps_2_desugarer_transforms as n2t
import blame as bl
import on

// 🌸🌸🌸🌸🌸🌸🌸
// 🌸 menus~ 🌸
// 🌸🌸🌸🌸🌸🌸🌸

fn right_menu(document: VXML) -> VXML {
  let b = desugarer_blame(194)

  let first_chapter_title =
    document
    |> infra.v_children_with_tag("Chapter")
    |> list.first
    |> result.map(fn(chapter) { infra.v_first_attribute_with_key(chapter, "title") })
    |> result.map(fn(opt) { option.map(opt, fn(attr) {attr.value})})
    |> result.map(fn(opt) { option.unwrap(opt, "no title found")})
    |> result.unwrap("no title found")

  V(
    b,
    "RightMenu",
    [
      Attribute(b, "class", "menu-right"),
    ],
    [
      V(
        b,
        "a",
        [
          Attribute(b, "id", "next-page"),
          Attribute(b, "href", href(1, 0)),
        ],
        [
          T(b, [TextLine(b, "1. " <> first_chapter_title <> " >>")]),
        ]
      ),
    ]
  )
}

fn menu(document: VXML) -> VXML {
  let b = desugarer_blame(225)

  let course_homepage_link =
    case infra.v_first_attribute_with_key(document, "course_homepage") {
      None -> "no url for course homepage"
      Some(x) -> x.value
    }

  let left_menu =
    V(
      b,
      "LeftMenu",
      [
        Attribute(b, "class", "menu-left")
      ],
      [
        V(b, "a", [Attribute(b, "href", course_homepage_link)], [T(b, [TextLine(b, "zür Kursübersicht")])])
      ]
    )

  V(
    b,
    "nav",
    [
      Attribute(b, "class", "menu"),
    ],
    [
      left_menu,
      right_menu(document),
    ]
  )
}

// 🌸🌸🌸🌸🌸🌸🌸
// 🌸 header 🌸
// 🌸🌸🌸🌸🌸🌸🌸

fn header(document: VXML) -> VXML {
  let b = desugarer_blame(140)

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
    b,
    "header",
    [
      Attribute(b, "class", "index__header"),
    ],
    [
      V(
        b,
        "h1",
        [
          Attribute(b, "class", "index__header__title"),
        ],
        [
          T(b, [TextLine(b, title)]),
        ],
      ),
      V(
        b,
        "span",
        [
          Attribute(b, "class", "index__header__subtitle"),
        ],
        [
          T(b, [TextLine(b, program)]),
        ],
      ),
      V(
        b,
        "span",
        [
          Attribute(b, "class", "index__header__subtitle"),
        ],
        [
          T(b, [TextLine(b, lecturer <> ", " <> institution)]),
        ],
      )
    ]
  )
}

// 🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸
// 🌸 table of contents~~ 🌸
// 🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸

type ChapterOrSubchapterTitle = List(VXML)

type SubchapterTitle = ChapterOrSubchapterTitle
type ChapterTitle = ChapterOrSubchapterTitle

type SubchapterNo = Int
type ChapterNo = Int

type SubchapterInfo = #(ChapterNo, SubchapterNo, SubchapterTitle)
type ChapterInfo = #(ChapterNo, ChapterTitle, List(SubchapterInfo))

fn extract_title(
  chapter_or_subchapter ch: VXML,
  title_tag t: String,
) -> Result(ChapterOrSubchapterTitle, DesugaringError) {
  use title_element <- on.ok(infra.v_unique_child_with_tag_with_desugaring_error(ch, t))
  let assert V(_, _, _, children) = title_element
  let assert [T(b, contents), ..rest] = children
  let assert Ok(re) = regexp.from_string("^(\\d+)(\\.(\\d+)?)?\\s")
  let without_number =
    contents
    |> list.map(fn(line: TextLine) { line.content })
    |> string.join("")
    |> regexp.replace(re, _, "")
  Ok([T(b, [TextLine(b, without_number)]), ..rest])
}

fn extract_subchapter_info(subchapter: VXML, index: Int, ch_no: Int) {
  use title <- on.ok(extract_title(subchapter, "SubTitle"))
  Ok(#(ch_no, index + 1, title))
}

fn extract_subchapter_infos(
  chapter: VXML,
  ch_no: Int,
) -> Result(List(SubchapterInfo), DesugaringError) {
  chapter
  |> infra.v_children_with_tag("Sub")
  |> infra.index_try_map(fn(s, i) { extract_subchapter_info(s, i, ch_no) })
}

fn extract_chapter_info(ch: VXML, index: Int) -> Result(ChapterInfo, DesugaringError) {
  use title <- on.ok(extract_title(ch, "ChapterTitle"))
  use infos <- on.ok(extract_subchapter_infos(ch, index + 1))
  Ok(#(index + 1, title, infos))
}

fn extract_chapter_infos(root: VXML) -> Result(List(ChapterInfo), DesugaringError) {
  root
  |> infra.v_children_with_tag("Chapter")
  |> infra.index_try_map(extract_chapter_info)
}

fn href(chapter_no: Int, sub_no: Int) -> String {
  "./" <> ins(chapter_no) <> "-" <> ins(sub_no) <> ".html"
}

fn subchapter_item(subchapter: SubchapterInfo) -> VXML {
  let b = desugarer_blame(213)
  let #(chapter_no, subchapter_no, title) = subchapter
  V(
    b,
    "li",
    [],
    [
      V(
        b,
        "a",
        [
          Attribute(b, "href", href(chapter_no, subchapter_no)),
        ],
        title,
      )
    ]
  )
}

fn chapter_item(
  chapter: ChapterInfo,
) -> VXML {
  let b = desugarer_blame(101)
  let #(chapter_no, chapter_title, subchapters) = chapter
  let subchapters_ol = case subchapters {
    [] -> []
    _ -> [
      V(
        b,
        "ol",
        [],
        list.map(subchapters, subchapter_item),
      )
    ]
  }

  let link = V(
    b,
    "a",
    [
      Attribute(b, "href", href(chapter_no, 0)),
    ],
    chapter_title,
  )

  V(
    b,
    "li",
    [],
    [
      link,
      ..subchapters_ol,
    ],
  )
}

fn chapter_ol(chapters: List(ChapterInfo)) -> VXML {
  let b = desugarer_blame(254)
  V(
    b,
    "ol",
    [
      Attribute(b, "class", "index__toc"),
    ],
    list.map(chapters, chapter_item),
  )
}

fn index(root: VXML) -> Result(VXML, DesugaringError) {
  use chapter_infos <- on.ok(extract_chapter_infos(root))
  Ok(V(
    desugarer_blame(282),
    "Index",
    [
      Attribute(desugarer_blame(284), "path", "./index.html"),
    ],
    [
      menu(root),
      header(root),
      chapter_ol(chapter_infos),
    ],
  ))
}

fn at_root(root: VXML) -> Result(VXML, DesugaringError) {
  let assert V(_, "Document", _, children) = root
  use index <- on.ok(index(root))
  Ok(V(..root, children: [index, ..children]))
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
/// generate ti3 Index element
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
                      <> ol
                        class=index__toc
                        <> li
                          <> a
                            href=./1-0.html
                            <>
                              \"Introduction\"
                          <> ol
                            <> li
                              <> a
                                href=./1-1.html
                                <>
                                  \"Overview\"
                            <> li
                              <> a
                                href=./1-2.html
                                <>
                                  \"Goals\"
                        <> li
                          <> a
                            href=./2-0.html
                            <>
                              \"Fundamentals\"
                          <> ol
                            <> li
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
