import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugaringError, type TrafficLight, Continue,
  DesugaringError, GoBack,
}
import desugaring/nodemaps_2_transform as n2t
import gleam/list
import gleam/option.{type Option}
import gleam/string.{inspect as ins}
import on
import vxml.{type VXML, Attr, Line, T, V}
import vxml/blame.{type Blame} as bl

pub const name = "ti2_create_index"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Generates the ti2 Index element from the document's
/// chapter and subchapter structure.
pub fn constructor() -> Desugarer {
  authoring.no_param_desugarer(
    name: name,
    transform: inner_param_to_transform(),
  )
}

// 🌸🌸🌸🌸🌸🌸🌸
// 🌸 header 🌸
// 🌸🌸🌸🌸🌸🌸🌸

fn attribute_text(root: VXML, key: String) -> Option(#(Blame, String)) {
  core.v_first_attr_with_key(root, key)
  |> option.map(fn(attr) {
    #(attr.blame |> bl.advance(string.length(key) + 1), attr.val)
  })
}

fn header(root: VXML) -> VXML {
  let b = desugarer_blame(41)
  let title = attribute_text(root, "title") |> option.unwrap(#(b, "no title"))
  let program =
    attribute_text(root, "program") |> option.unwrap(#(b, "no program"))
  let institution =
    attribute_text(root, "institution") |> option.unwrap(#(b, "no institution"))
  let lecturer =
    attribute_text(root, "lecturer") |> option.unwrap(#(b, "no lecturer"))
  V(
    b,
    "header",
    [
      Attr(b, "class", "index__header"),
    ],
    [
      V(
        b,
        "h1",
        [
          Attr(b, "class", "index__header__title"),
        ],
        [
          T(b, [Line(title.0, title.1)]),
        ],
      ),
      V(
        b,
        "div",
        [
          Attr(b, "class", "index__header__subtitle"),
        ],
        [
          T(b, [Line(program.0, program.1)]),
          V(b, "br", [], []),
          T(b, [
            Line(lecturer.0, lecturer.1 <> ","),
            Line(institution.0, institution.1),
          ]),
        ],
      ),
    ],
  )
}

// 🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸
// 🌸 gathering for table of contents 🌸
// 🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸

type Title =
  List(VXML)

type SubInfo {
  SubInfo(title: Title)
}

type ChapterInfo {
  ChapterInfo(title: Title, subs: List(SubInfo))
}

type ChapterOrSub {
  Chapter
  Sub
}

fn gather_title(
  vxml: VXML,
  chapter_or_sub: ChapterOrSub,
) -> Result(Title, DesugaringError) {
  let title_tag = case chapter_or_sub {
    Chapter -> "ChapterTitle"
    Sub -> "SubTitle"
  }
  use title_element <- on.ok(core.v_unique_child(vxml, title_tag))
  let assert V(_, _, _, children) = title_element
  // so that we can stomach both the cases where the
  // title has already been wrapped in <p></p> or not:
  case children {
    [V(_, "p", _, children)] -> Ok(children)
    _ -> Ok(children)
  }
}

fn add_chapter_with_title_to_state(
  state: List(ChapterInfo),
  title: Title,
) -> List(ChapterInfo) {
  let chapter = ChapterInfo(title, [])
  [chapter, ..state]
}

fn add_sub_with_title_to_state(
  state: List(ChapterInfo),
  title: Title,
) -> Result(List(ChapterInfo), DesugaringError) {
  case state {
    [ChapterInfo(_, subs) as first, ..rest] -> {
      let first = ChapterInfo(..first, subs: [SubInfo(title), ..subs])
      Ok([first, ..rest])
    }
    [] ->
      Error(DesugaringError(
        bl.no_blame,
        "encountered a Sub element before any Chapter element",
      ))
  }
}

fn chapter_info_information_collector(
  vxml: VXML,
  state: List(ChapterInfo),
) -> Result(#(List(ChapterInfo), TrafficLight), DesugaringError) {
  case vxml {
    V(_, "Document", _, _) -> Ok(#(state, Continue))

    V(_, "Chapter", _, _) -> {
      use title <- on.ok(gather_title(vxml, Chapter))
      Ok(#(state |> add_chapter_with_title_to_state(title), Continue))
    }

    V(_, "Sub", _, _) -> {
      use title <- on.ok(gather_title(vxml, Sub))
      use state <- on.ok(add_sub_with_title_to_state(state, title))
      Ok(#(state, GoBack))
    }

    _ -> Ok(#(state, GoBack))
  }
}

fn gather_chapter_infos(
  root: VXML,
) -> Result(List(ChapterInfo), DesugaringError) {
  n2t.early_return_stateful_visit(root, [], chapter_info_information_collector)
}

// 🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸
// 🌸 table of contents 🌸
// 🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸

fn href(chapter_no: Int, sub_no: Int) -> String {
  "./" <> ins(chapter_no) <> "-" <> ins(sub_no) <> ".html"
}

fn sub_item(ch_no: Int, sub_no: Int, sub: SubInfo) -> VXML {
  let b = desugarer_blame(185)
  let SubInfo(title) = sub
  V(b, "li", [], [
    V(
      b,
      "a",
      [
        Attr(b, "href", href(ch_no, sub_no)),
      ],
      title,
    ),
  ])
}

fn chapter_item(ch_no: Int, chapter: ChapterInfo) -> VXML {
  let b = desugarer_blame(200)
  let ChapterInfo(title, subs) = chapter
  let subchapters_ol = case subs {
    [] -> []
    _ -> [
      V(
        b,
        "ol",
        [],
        list.index_map(subs |> list.reverse, fn(sub, i) {
          sub_item(ch_no, i + 1, sub)
        }),
      ),
    ]
  }

  let link =
    V(
      b,
      "a",
      [
        Attr(b, "href", href(ch_no, 0)),
      ],
      title,
    )

  V(b, "li", [], [link, ..subchapters_ol])
}

fn chapter_ol(chapters: List(ChapterInfo)) -> VXML {
  let b = desugarer_blame(230)
  V(
    b,
    "ol",
    [
      Attr(b, "class", "index__toc"),
    ],
    list.index_map(chapters |> list.reverse, fn(ch, i) {
      chapter_item(i + 1, ch)
    }),
  )
}

// 🌸🌸🌸🌸🌸🌸🌸
// 🌸 main 🌸
// 🌸🌸🌸🌸🌸🌸🌸

fn index(root: VXML) -> Result(VXML, DesugaringError) {
  use chapter_infos <- on.ok(gather_chapter_infos(root))

  Ok(
    V(
      desugarer_blame(252),
      "Index",
      [
        Attr(desugarer_blame(255), "path", "./index.html"),
      ],
      [
        header(root),
        chapter_ol(chapter_infos),
      ],
    ),
  )
}

fn at_root(root: VXML) -> Result(VXML, DesugaringError) {
  case root {
    V(_, "Document", _, children) -> {
      use index <- on.ok(index(root))
      Ok(V(..root, children: [index, ..children]))
    }
    V(blame, _, _, _) | T(blame, _) ->
      Error(DesugaringError(blame, "expected a Document root element"))
  }
}

fn inner_param_to_transform() -> core.DesugarerTransform {
  at_root
  |> n2t.node_to_node_2_desugarer_transform_without_walking
}

fn desugarer_blame(line_no: Int) {
  bl.Des([], name, line_no)
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
fn assertive_tests_data() -> List(core.AssertiveTestDataNoParam) {
  [
    core.AssertiveTestDataNoParam(
      source: "
                <> Document
                  title=Course title
                  program=Program
                  institution=Institution
                  lecturer=Lecturer
                  <> Chapter
                    <> ChapterTitle
                      <>
                        'Introduction'
                    <> Sub
                      <> SubTitle
                        <>
                          'Details'
                ",
      expected: "
                <> Document
                  title=Course title
                  program=Program
                  institution=Institution
                  lecturer=Lecturer
                  <> Index
                    path=./index.html
                    <> header
                      class=index__header
                      <> h1
                        class=index__header__title
                        <>
                          'Course title'
                      <> div
                        class=index__header__subtitle
                        <>
                          'Program'
                        <> br
                        <>
                          'Lecturer,'
                          'Institution'
                    <> ol
                      class=index__toc
                      <> li
                        <> a
                          href=./1-0.html
                          <>
                            'Introduction'
                        <> ol
                          <> li
                            <> a
                              href=./1-1.html
                              <>
                                'Details'
                  <> Chapter
                    <> ChapterTitle
                      <>
                        'Introduction'
                    <> Sub
                      <> SubTitle
                        <>
                          'Details'
                ",
    ),
  ]
}

pub fn assertive_tests() {
  core.assertive_test_collection_from_data_no_param(
    name,
    assertive_tests_data(),
    constructor,
  )
}
