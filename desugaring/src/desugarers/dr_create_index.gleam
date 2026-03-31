import gleam/list
import gleam/option.{type Option}
import gleam/string.{inspect as ins}
import infrastructure.{
  type Desugarer,
  type DesugaringError,
  type TrafficLight,
  Desugarer,
  Continue,
  GoBack,
} as infra
import vxml.{
  type VXML,
  Attr,
  Line,
  V,
  T,
}
import nodemaps_2_desugarer_transforms as n2t
import blame.{type Blame} as bl
import on

// 🌸🌸🌸🌸🌸🌸🌸
// 🌸 header 🌸
// 🌸🌸🌸🌸🌸🌸🌸

fn get(root: VXML, key: String) -> Option(#(Blame, String)) {
  infra.v_first_attr_with_key(root, key)
  |> option.map(fn(attr) { #(attr.blame |> bl.advance(string.length(key) + 1), attr.val) })
}

fn header(root: VXML) -> VXML {
  let b = desugarer_blame(33)
  let title = get(root, "title") |> option.unwrap(#(b, "no title"))
  let course = get(root, "course") |> option.unwrap(#(b, "no course"))
  let term = get(root, "term") |> option.unwrap(#(b, "no term"))
  let lecturer = get(root, "lecturer") |> option.unwrap(#(b, "no lecturer"))
  let department = get(root, "department") |> option.unwrap(#(b, "department"))
  let institution = get(root, "institution") |> option.unwrap(#(b, "no institution"))
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
          Attr(b, "class", "index__header__sectiontitle"),
        ],
        [
          T(b, [Line(course.0, course.1 <> ","), Line(term.0, term.1)]),
          V(b, "br", [], []),
          T(b, [Line(lecturer.0, lecturer.1 <> ","), Line(department.0, department.1 <> ","), Line(institution.0, institution.1)]),
        ],
      ),
    ]
  )
}

// 🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸
// 🌸 gathering for table of contents~ 🌸
// 🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸

type Title =
  List(VXML)

type SubSectionInfo {
  SubSectionInfo(
    title: Title
  )
}

type SectionInfo {
  SectionInfo(
    title: Title,
    subsections: List(SubSectionInfo)
  )
}

type ChapterInfo {
  ChapterInfo(
    title: Title,
    sections: List(SectionInfo)
  )
}

type ChapterOrSection {
  Chapter
  Section
  SubSection
}

fn gather_title(
  vxml: VXML,
  chapter_or_section: ChapterOrSection,
) -> Result(Title, DesugaringError) {
  let title_tag = case chapter_or_section {
    Chapter -> "ChapterTitle"
    Section -> "SectionTitle"
    SubSection -> "SubSectionTitle"
  }
  use title_element <- on.ok(infra.v_unique_child(vxml, title_tag))
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

fn add_section_with_title_to_state(
  state: List(ChapterInfo),
  title: Title,
) -> List(ChapterInfo) {
  let assert [ChapterInfo(_, sections) as first, ..rest] = state
  let first = ChapterInfo(..first, sections: [SectionInfo(title, []), ..sections])
  [first, ..rest]
}

fn add_subsection_with_title_to_state(
  state: List(ChapterInfo),
  title: Title,
) -> List(ChapterInfo) {
  let assert [ChapterInfo(_, [SectionInfo(_, subsections) as section, ..sections]) as chapter, ..rest] = state
  let section = SectionInfo(..section, subsections: [SubSectionInfo(title), ..subsections])
  let chapter = ChapterInfo(..chapter, sections: [section, ..sections])
  [chapter, ..rest]
}

fn chapter_info_information_collector(
  vxml: VXML,
  state: List(ChapterInfo),
) -> Result(#(List(ChapterInfo), TrafficLight), DesugaringError) {
  case vxml {
    V(_, "Document", _, _) ->
      Ok(#(state, Continue))

    V(_, "Chapter", _, _) -> {
      use title <- on.ok(gather_title(vxml, Chapter))
      Ok(#(state |> add_chapter_with_title_to_state(title), Continue))
    }

    V(_, "Section", _, _) -> {
      use title <- on.ok(gather_title(vxml, Section))
      Ok(#(state |> add_section_with_title_to_state(title), Continue))
    }
    
    V(_, "SubSection", _, _) -> {
      use title <- on.ok(gather_title(vxml, SubSection))
      Ok(#(state |> add_subsection_with_title_to_state(title), GoBack))
    }

    _ -> Ok(#(state, GoBack))
  }
}

fn gather_chapter_infos(root: VXML) -> Result(List(ChapterInfo), DesugaringError) {
  n2t.early_return_identity_stateful_walk(
    root,
    [],
    chapter_info_information_collector,
  )
}

// 🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸
// 🌸 table of contents~~ 🌸
// 🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸

fn href(chapter_no: Int, section_no: Int, subsection_no: Int) -> String {
  case subsection_no {
    0 -> "./" <> ins(chapter_no) <> "-" <> ins(section_no) <> ".html"
    _ -> "./" <> ins(chapter_no) <> "-" <> ins(section_no) <> "-" <> ins(subsection_no) <> ".html"
  }
}

fn subsection_item(ch_no: Int, section_no: Int, subsection_no: Int, subsection: SubSectionInfo) -> VXML {
  let b = desugarer_blame(179)
  let SubSectionInfo(title) = subsection
  
  V(
    b,
    "li",
    [],
    [
      V(
        b,
        "a",
        [
          Attr(b, "href", href(ch_no, section_no, subsection_no)),
        ],
        title,
      ),
    ],
  )
}

fn section_item(ch_no: Int, section_no: Int, section: SectionInfo) -> VXML {
  let b = desugarer_blame(200)
  let SectionInfo(title, subsections) = section
  let subsections_ol = case subsections {
    [] -> []
    _ -> [
      V(
        b,
        "ol",
        [],
        list.index_map(subsections |> list.reverse, fn (subsection, i) { subsection_item(ch_no, section_no, i + 1, subsection) }),
      ),
    ]
  }
  
  V(
    b,
    "li",
    [],
    [
      V(
        b,
        "a",
        [
          Attr(b, "href", href(ch_no, section_no, 0)),
        ],
        title,
      ),
      ..subsections_ol
    ],
  )
}

fn chapter_item(
  ch_no: Int,
  chapter: ChapterInfo,
) -> VXML {
  let b = desugarer_blame(236)
  let ChapterInfo(title, sections) = chapter
  let sections_ol = case sections {
    [] -> []
    _ -> [
      V(
        b,
        "ol",
        [],
        list.index_map(sections |> list.reverse, fn (section, i) { section_item(ch_no, i + 1, section) }),
      ),
    ]
  }

  let link = V(
    b,
    "a",
    [
      Attr(b, "href", href(ch_no, 0, 0)),
    ],
    title,
  )

  V(
    b,
    "li",
    [],
    [
      link,
      ..sections_ol,
    ],
  )
}

fn chapter_ol(chapters: List(ChapterInfo)) -> VXML {
  let b = desugarer_blame(228)
  V(
    b,
    "ol",
    [
      Attr(b, "class", "index__toc"),
    ],
    list.index_map(chapters |> list.reverse, fn(ch, i) { chapter_item(i + 1, ch) }),
  )
}

// 🌸🌸🌸🌸🌸🌸🌸
// 🌸 main~~ 🌸
// 🌸🌸🌸🌸🌸🌸🌸

fn index(root: VXML) -> Result(VXML, DesugaringError) {
  use chapter_infos <- on.ok(gather_chapter_infos(root))

  Ok(V(
    desugarer_blame(247),
    "Index",
    [
      Attr(desugarer_blame(250), "path", "./index.html"),
    ],
    [
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

pub const name = "dr_create_index"
fn desugarer_blame(line_no: Int) { bl.Des([], name, line_no) }

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// generate dr Index element
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
