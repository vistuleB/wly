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

type Title =
  List(VXML)

type SubInfo {
  SubInfo(
    title: Title,
    no: Int,
  )
}

type ChapterInfo {
  ChapterInfo(
    title: Title,
    no: Int,
    subs: List(SubInfo)
  )
}

type ChapterOrSub {
  Chapter
  Sub
}

type ChapterInfoGatheringState {
  ChapterInfoGatheringState(
    chapters: List(ChapterInfo),
    ch_no: Int,
    sub_no: Int,
  )
}

fn chapter_info_gatherer_v_before(
  vxml: VXML,
  state: ChapterInfoGatheringState,
) -> Result(#(VXML, ChapterInfoGatheringState, TrafficLight), DesugaringError) {
  case vxml {
    V(_, "Document", _, _) ->
      Ok(#(vxml, state, Continue))

    V(_, "Chapter", _, _) -> {
      let ChapterInfoGatheringState(chapters, ch_no, _) = state
      use title <- on.ok(harvest_title(vxml, Chapter))
      let chapters = [ChapterInfo(title, ch_no + 1, []), ..chapters]
      let state = ChapterInfoGatheringState(chapters, ch_no + 1, 0)
      Ok(#(vxml, state, Continue))
    }

    V(_, "Sub", _, _) -> {
      let assert ChapterInfoGatheringState([ChapterInfo(_, _, subs) as last, ..rest], ch_no, sub_no) = state
      use title <- on.ok(harvest_title(vxml, Sub))
      let chapters = [ChapterInfo(..last, subs: [SubInfo(title, sub_no + 1), ..subs]), ..rest]
      let state = ChapterInfoGatheringState(chapters, ch_no, sub_no + 1)
      Ok(#(vxml, state, GoBack))
    }

    _ -> Ok(#(vxml, state, GoBack))
  }
}

fn chapter_info_gatherer_nodemap() -> n2t.EarlyReturnOneToOneBeforeAndAfterStatefulNodeMap(ChapterInfoGatheringState) {
  n2t.EarlyReturnOneToOneBeforeAndAfterStatefulNodeMap(
    v_before_transforming_children: chapter_info_gatherer_v_before,
    v_after_transforming_children: n2t.before_and_after_keep_latest_state,
    t_nodemap: n2t.before_and_after_identity,
  )
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
) -> Result(SubInfo, DesugaringError) {
  use title <- on.ok(harvest_title(subchapter, Sub))
  Ok(SubInfo(title, index + 1))
}

fn harvest_subchapter_infos(
  chapter: VXML,
) -> Result(List(SubInfo), DesugaringError) {
  chapter
  |> infra.v_children_with_tag("Sub")
  |> infra.index_try_map(harvest_subchapter_info)
}

fn harvest_chapter_info(
  ch: VXML,
  index: Int,
) -> Result(ChapterInfo, DesugaringError) {
  use title <- on.ok(harvest_title(ch, Chapter))
  use subs <- on.ok(harvest_subchapter_infos(ch))
  Ok(ChapterInfo(title, index + 1, subs))
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

fn subchapter_item(ch_no: Int, sub: SubInfo) -> VXML {
  let b = desugarer_blame(161)
  let SubInfo(title, sub_no) = sub
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
  chapter: ChapterInfo,
) -> VXML {
  let b = desugarer_blame(183)
  let ChapterInfo(title, ch_no, subs) = chapter
  let subchapters_ol = case subs {
    [] -> []
    _ -> [
      V(
        b,
        "ol",
        [],
        list.map(subs, subchapter_item(ch_no, _)),
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
  use #(_, ChapterInfoGatheringState(chapter_infos, _, _)) <- on.ok(
    n2t.early_return_one_to_one_before_and_after_stateful_nodemap_traverse_tree(
      ChapterInfoGatheringState([], 0, 0),
      root,
      chapter_info_gatherer_nodemap(),
    )
  )
  // use chapter_infos <- on.ok(harvest_chapter_infos(root))

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
