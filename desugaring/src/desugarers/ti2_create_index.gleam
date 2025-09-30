import gleam/list
import gleam/option.{Some,None}
import gleam/string.{inspect as ins}
import gleam/regexp.{type Regexp}
import infrastructure.{
  type Desugarer,
  type DesugaringError,
  Desugarer,
} as infra
import vxml.{
  type VXML,
  Attribute,
  TextLine,
  V,
  T,
}
import nodemaps_2_desugarer_transforms as n2t
import blame as bl
import on

// 🌸🌸🌸🌸🌸🌸🌸
// 🌸 header 🌸
// 🌸🌸🌸🌸🌸🌸🌸

fn header(document: VXML) -> VXML {
  let b = desugarer_blame(26)

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
        "div",
        [
          Attribute(b, "class", "index__header__subtitle"),
        ],
        [
          T(b, [TextLine(b, program)]),
          V(b, "br", [], []),
          T(b, [TextLine(b, lecturer <> ", " <> institution)]),
        ],
      ),
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
  ch_or_sub: VXML,
  title_tag: String,
  re: Regexp,
) -> Result(ChapterOrSubchapterTitle, DesugaringError) {
  use title_element <- on.ok(infra.v_unique_child_with_tag_with_desugaring_error(ch_or_sub, title_tag))
  let assert V(_, _, _, children) = title_element
  let assert [T(b, [first, ..more]), ..rest] = children
  let first = TextLine(
    desugarer_blame(110),
    first.content |> regexp.replace(re, _, "")
  )
  Ok([T(b, [first, ..more]), ..rest])
}

fn extract_subchapter_info(
  subchapter: VXML,
  index: Int,
  ch_no: Int,
  re: Regexp,
) {
  use title <- on.ok(extract_title(subchapter, "SubTitle", re))
  Ok(#(ch_no, index + 1, title))
}

fn extract_subchapter_infos(
  chapter: VXML,
  ch_no: Int,
  re: Regexp,
) -> Result(List(SubchapterInfo), DesugaringError) {
  chapter
  |> infra.v_children_with_tag("Sub")
  |> infra.index_try_map(fn(s, i) { extract_subchapter_info(s, i, ch_no, re) })
}

fn extract_chapter_info(
  ch: VXML,
  index: Int,
  re: Regexp,
) -> Result(ChapterInfo, DesugaringError) {
  use title <- on.ok(extract_title(ch, "ChapterTitle", re))
  use infos <- on.ok(extract_subchapter_infos(ch, index + 1, re))
  Ok(#(index + 1, title, infos))
}

fn extract_chapter_infos(
  root: VXML,
  re: Regexp,
) -> Result(List(ChapterInfo), DesugaringError) {
  root
  |> infra.v_children_with_tag("Chapter")
  |> infra.index_try_map(
    fn(c, i) { extract_chapter_info(c, i, re) }
  )
}

fn href(chapter_no: Int, sub_no: Int) -> String {
  "./" <> ins(chapter_no) <> "-" <> ins(sub_no) <> ".html"
}

fn subchapter_item(subchapter: SubchapterInfo) -> VXML {
  let b = desugarer_blame(160)
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
  let b = desugarer_blame(182)
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
  let b = desugarer_blame(217)
  V(
    b,
    "ol",
    [
      Attribute(b, "class", "index__toc"),
    ],
    list.map(chapters, chapter_item),
  )
}

// 🌸🌸🌸🌸🌸🌸🌸
// 🌸 main~~ 🌸
// 🌸🌸🌸🌸🌸🌸🌸

fn index(root: VXML) -> Result(VXML, DesugaringError) {
  let assert Ok(re) = regexp.from_string("^(\\d+)(\\.(\\d+)?)?\\s")
  use chapter_infos <- on.ok(extract_chapter_infos(root, re))
  Ok(V(
    desugarer_blame(236),
    "Index",
    [
      Attribute(desugarer_blame(239), "path", "./index.html"),
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

pub const name = "ti2_create_index"
fn desugarer_blame(line_no: Int) { bl.Des([], name, line_no) }

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// generate ti2 Index element
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
