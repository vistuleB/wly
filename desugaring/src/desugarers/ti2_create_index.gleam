import gleam/list
import gleam/option.{Some,None}
import gleam/string.{inspect as ins}
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

// 🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸
// 🌸 data harvesting for table of contents~~~ 🌸
// 🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸

type Title = List(VXML)
type SubNo = Int
type ChapterNo = Int
type SubInfo = #(ChapterNo, SubNo, Title)
type ChapterInfo = #(ChapterNo, Title, List(SubInfo))
type ChapterOrSub {
  Chapter
  Sub
}

fn harvest_title(
  vxml: VXML,
  chapter_or_sub: ChapterOrSub,
) -> Result(Title, DesugaringError) {
  let title_tag = case chapter_or_sub {
    Chapter -> "ChapterTitle"
    Sub -> "SubTitle"
  }
  use title_element <- on.ok(infra.v_unique_child(vxml, title_tag))
  let assert V(_, _, _, children) = title_element
  Ok(children)
}

fn harvest_subchapter_info(
  subchapter: VXML,
  index: Int,
  ch_no: Int,
) {
  use title <- on.ok(harvest_title(subchapter, Sub))
  Ok(#(ch_no, index + 1, title))
}

fn harvest_subchapter_infos(
  chapter: VXML,
  ch_no: Int,
) -> Result(List(SubInfo), DesugaringError) {
  chapter
  |> infra.v_children_with_tag("Sub")
  |> infra.index_try_map(fn(s, i) { harvest_subchapter_info(s, i, ch_no) })
}

fn harvest_chapter_info(
  ch: VXML,
  index: Int,
) -> Result(ChapterInfo, DesugaringError) {
  use title <- on.ok(harvest_title(ch, Chapter))
  use infos <- on.ok(harvest_subchapter_infos(ch, index + 1))
  Ok(#(index + 1, title, infos))
}

fn harvest_chapter_infos(
  root: VXML,
) -> Result(List(ChapterInfo), DesugaringError) {
  root
  |> infra.v_children_with_tag("Chapter")
  |> infra.index_try_map(harvest_chapter_info)
}

// 🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸
// 🌸 table of contents~~ 🌸
// 🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸

fn href(chapter_no: Int, sub_no: Int) -> String {
  "./" <> ins(chapter_no) <> "-" <> ins(sub_no) <> ".html"
}

fn subchapter_item(subchapter: SubInfo) -> VXML {
  let b = desugarer_blame(161)
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
    ],
  )
}

fn chapter_item(
  chapter: ChapterInfo,
) -> VXML {
  let b = desugarer_blame(183)
  let #(chapter_no, chapter_title, subchapters) = chapter
  let subchapters_ol = case subchapters {
    [] -> []
    _ -> [
      V(
        b,
        "ol",
        [],
        list.map(subchapters, subchapter_item),
      ),
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
  let b = desugarer_blame(218)
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
  use chapter_infos <- on.ok(harvest_chapter_infos(root))
  Ok(V(
    desugarer_blame(237),
    "Index",
    [
      Attribute(desugarer_blame(240), "path", "./index.html"),
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
