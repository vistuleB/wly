import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugaringError, type TrafficLight, Continue, GoBack,
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

fn get(root: VXML, key: String) -> Option(#(Blame, String)) {
  core.v_first_attr_with_key(root, key)
  |> option.map(fn(attr) {
    #(attr.blame |> bl.advance(string.length(key) + 1), attr.val)
  })
}

fn header(root: VXML) -> VXML {
  let b = desugarer_blame(40)
  let title = get(root, "title") |> option.unwrap(#(b, "no title"))
  let program = get(root, "program") |> option.unwrap(#(b, "no program"))
  let institution =
    get(root, "institution") |> option.unwrap(#(b, "no institution"))
  let lecturer = get(root, "lecturer") |> option.unwrap(#(b, "no lecturer"))
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
// 🌸 gathering for table of contents~ 🌸
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
) -> List(ChapterInfo) {
  let assert [ChapterInfo(_, subs) as first, ..rest] = state
  let first = ChapterInfo(..first, subs: [SubInfo(title), ..subs])
  [first, ..rest]
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
      Ok(#(state |> add_sub_with_title_to_state(title), GoBack))
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
// 🌸 table of contents~~ 🌸
// 🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸

fn href(chapter_no: Int, sub_no: Int) -> String {
  "./" <> ins(chapter_no) <> "-" <> ins(sub_no) <> ".html"
}

fn sub_item(ch_no: Int, sub_no: Int, sub: SubInfo) -> VXML {
  let b = desugarer_blame(173)
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
  let b = desugarer_blame(188)
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
  let b = desugarer_blame(218)
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
// 🌸 main~~ 🌸
// 🌸🌸🌸🌸🌸🌸🌸

fn index(root: VXML) -> Result(VXML, DesugaringError) {
  use chapter_infos <- on.ok(gather_chapter_infos(root))

  Ok(
    V(
      desugarer_blame(240),
      "Index",
      [
        Attr(desugarer_blame(243), "path", "./index.html"),
      ],
      [
        header(root),
        chapter_ol(chapter_infos),
      ],
    ),
  )
}

fn at_root(root: VXML) -> Result(VXML, DesugaringError) {
  let assert V(_, "Document", _, children) = root
  use index <- on.ok(index(root))
  Ok(V(..root, children: [index, ..children]))
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
  []
}

pub fn assertive_tests() {
  core.assertive_test_collection_from_data_no_param(
    name,
    assertive_tests_data(),
    constructor,
  )
}
