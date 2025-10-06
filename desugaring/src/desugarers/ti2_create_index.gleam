import gleam/list
import gleam/option.{Some,None}
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
  let b = desugarer_blame(28)

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

// 🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸
// 🌸 gathering for table of contents~ 🌸
// 🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸

type Title =
  List(VXML)

type SubInfo {
  SubInfo(
    title: Title,
  )
}

type ChapterInfo {
  ChapterInfo(
    title: Title,
    subs: List(SubInfo)
  )
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

fn add_sub_with_title_to_state(
  state: List(ChapterInfo),
  title: Title,
) -> List(ChapterInfo) {
  let assert [ChapterInfo(_, subs) as first, ..rest] = state
  let first = ChapterInfo(..first, subs: [SubInfo(title), ..subs])
  [first, ..rest]
}

fn chapter_info_information_gatherer(
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

    V(_, "Sub", _, _) -> {
      use title <- on.ok(gather_title(vxml, Sub))
      Ok(#(state |> add_sub_with_title_to_state(title), GoBack))
    }

    _ -> Ok(#(state, GoBack))
  }
}

fn gather_chapter_infos(root: VXML) -> Result(List(ChapterInfo), DesugaringError) {
  n2t.early_return_information_gatherer_traverse_tree(
    root,
    [],
    chapter_info_information_gatherer,
  )
}

// 🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸
// 🌸 table of contents~~ 🌸
// 🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸

fn href(chapter_no: Int, sub_no: Int) -> String {
  "./" <> ins(chapter_no) <> "-" <> ins(sub_no) <> ".html"
}

fn sub_item(ch_no: Int, sub_no: Int, sub: SubInfo) -> VXML {
  let b = desugarer_blame(186)
  let SubInfo(title) = sub
  V(
    b,
    "li",
    [],
    [
      V(
        b,
        "a",
        [
          Attribute(b, "href", href(ch_no, sub_no)),
        ],
        title,
      )
    ],
  )
}

fn chapter_item(
  ch_no: Int,
  chapter: ChapterInfo,
) -> VXML {
  let b = desugarer_blame(209)
  let ChapterInfo(title, subs) = chapter
  let subchapters_ol = case subs {
    [] -> []
    _ -> [
      V(
        b,
        "ol",
        [],
        list.index_map(subs |> list.reverse, fn (sub, i) { sub_item(ch_no, i + 1, sub) }),
      ),
    ]
  }

  let link = V(
    b,
    "a",
    [
      Attribute(b, "href", href(ch_no, 0)),
    ],
    title,
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
  let b = desugarer_blame(244)
  V(
    b,
    "ol",
    [
      Attribute(b, "class", "index__toc"),
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
    desugarer_blame(263),
    "Index",
    [
      Attribute(desugarer_blame(266), "path", "./index.html"),
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
