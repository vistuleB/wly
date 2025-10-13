import gleam/list
import gleam/string.{inspect as ins}
import gleam/option.{type Option, None, Some}
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
  type Attr,
  Attr,
  V,
}
import nodemaps_2_desugarer_transforms as n2t
import blame as bl
import on

// ************************************************************
// common types
// ************************************************************

type Title = List(VXML)

type Page {
  Chapter(title: Title, number_chiron: String, ch_no: Int)
  Sub(title: Title, number_chiron: String, ch_no: Int, sub_no: Int)
}

// ************************************************************
// PAGE GATHERING: walking the tree to construct a List(Page)
// ************************************************************

type PageGatheringState {
  PageGatheringState(
    pages: List(Page),
    ch_no: Int,
    sub_no: Int,
  )
}

fn gather_title_and_chiron(
  vxml: VXML,
  tag: String,
) -> Result(#(Title, String), DesugaringError) {
  use title_element <- on.ok(infra.v_unique_child(vxml, tag))
  let assert V(blame, _, attrs, title) = title_element
  // so that we can stomach both the cases where the
  // title has already been wrapped in <p></p> or not:
  let title = case title {
    [V(_, "p", _, title)] -> title
    _ -> title
  }
  use chiron <- on.ok(infra.attrs_value_of_unique_key(attrs, "number-chiron", blame))
  Ok(#(title, chiron))
}

fn add_chapter_to_page_gathering_state(
  state: PageGatheringState,
  title: Title,
  chiron: String,
) -> PageGatheringState {
  let PageGatheringState(pages, ch_no, _) = state
  let pages = [Chapter(title, chiron, ch_no + 1), ..pages]
  PageGatheringState(pages, ch_no + 1, 0)
}

fn add_sub_to_page_gathering_state(
  state: PageGatheringState,
  title: Title,
  chiron: String,
) -> PageGatheringState {
  let PageGatheringState(pages, ch_no, sub_no) = state
  let pages = [Sub(title, chiron, ch_no, sub_no + 1), ..pages]
  PageGatheringState(pages, ch_no, sub_no + 1)
}

fn page_information_gatherer(
  vxml: VXML,
  state: PageGatheringState,
) -> Result(#(PageGatheringState, TrafficLight), DesugaringError) {
  case vxml {
    V(_, "Document", _, _) ->
      Ok(#(state, Continue))

    V(_, "Chapter", _, _) -> {
      use #(title, chiron) <- on.ok(gather_title_and_chiron(vxml, "ChapterTitle"))
      Ok(#(state |> add_chapter_to_page_gathering_state(title, chiron), Continue))
    }

    V(_, "Sub", _, _) -> {
      use #(title, chiron) <- on.ok(gather_title_and_chiron(vxml, "SubTitle"))
      Ok(#(state |> add_sub_to_page_gathering_state(title, chiron), GoBack))
    }

    _ -> Ok(#(state, GoBack))
  }
}

fn gather_pages(root: VXML) -> Result(List(Page), DesugaringError) {
  use PageGatheringState(pages, _, _) <- on.ok(
    n2t.early_return_information_gatherer_traverse_tree(
      root,
      PageGatheringState([], 0, 0),
      page_information_gatherer,
    )
  )

  pages |> list.reverse |> Ok
}

// ************************************************************
// PAGE DEPOSITING: walking the tree with Pages in hand to
// write the appropriate title elements to each page
// ************************************************************

type PageDepositorState = #(List(Page), List(Page))

fn attrs_4_page(
  page: Page
) -> List(Attr) {
  case page {
    Chapter(_, number_chiron, ch_no) -> [
      Attr(desugarer_blame(127), "ch_no", ins(ch_no)),
      Attr(desugarer_blame(128), "number-chiron", number_chiron),
    ]
    Sub(_, number_chiron, ch_no, sub_no) -> [
      Attr(desugarer_blame(131), "ch_no", ins(ch_no)),
      Attr(desugarer_blame(132), "sub_no", ins(sub_no)),
      Attr(desugarer_blame(133), "number-chiron", number_chiron),
    ]
  }
}

fn deposit_next(
  vxml: VXML,
  next: Option(Page),
) -> VXML {
  let assert V(_, _, _, children) = vxml
  use next <- on.none_some(next, vxml)
  let title = V(
    desugarer_blame(145),
    "NextChapterOrSubTitle",
    attrs_4_page(next),
    next.title,
  )
  V(..vxml, children: [title, ..children])
}

fn deposit_prev(
  vxml: VXML,
  prev: Option(Page),
) -> VXML {
  let assert V(_, _, _, children) = vxml
  use prev <- on.none_some(prev, vxml)
  let title = V(
    desugarer_blame(160),
    "PrevChapterOrSubTitle",
    attrs_4_page(prev),
    prev.title,
  )
  V(..vxml, children: [title, ..children])
}

fn prev_this_next_rest(
  previous: List(Page),
  upcoming: List(Page),
  expecting: Page,
) -> #(Option(Page), Page, Option(Page), List(Page)) {
  let prev = case previous {
    [first, ..] -> Some(first)
    _ -> None
  }
  let assert [this, ..upcoming] = upcoming
  let _  = case expecting {
    Chapter(..) -> {
      let assert Chapter(_, _, _) = this
      Nil
    }
    Sub(..) -> {
      let assert Sub(_, _, _, _) = this
      Nil
    }
  }
  let next = case upcoming {
    [first, ..] -> Some(first)
    _ -> None
  }
  #(prev, this, next, upcoming)
}

fn page_depositor_v_before(
  vxml: VXML,
  state: PageDepositorState,
) -> Result(#(VXML, PageDepositorState, TrafficLight), DesugaringError) {
  case vxml {
    V(_, "Document", _, _) -> Ok(#(vxml, state, Continue))
    V(_, "Index", _, _) -> {
      let assert #([], [next, ..]) = state
      let assert Chapter(_, _, _) = next
      let vxml = vxml |> deposit_next(Some(next))
      Ok(#(vxml, state, GoBack))
    }
    V(_, "Chapter", _, _) -> {
      let #(previous, upcoming) = state
      let #(prev, this, next, upcoming) = prev_this_next_rest(previous, upcoming, Chapter([], "", 0))
      let vxml = vxml |> deposit_prev(prev) |> deposit_next(next)
      Ok(#(vxml, #([this, ..previous], upcoming), Continue))
    }
    V(_, "Sub", _, _) -> {
      let #(previous, upcoming) = state
      let #(prev, this, next, upcoming) = prev_this_next_rest(previous, upcoming, Sub([], "", 0, 0))
      let vxml = vxml |> deposit_prev(prev) |> deposit_next(next)
      Ok(#(vxml, #([this, ..previous], upcoming), GoBack))
    }
    _ -> Ok(#(vxml, state, GoBack))
  }
}

fn page_depositor_nodemap() -> n2t.EarlyReturnOneToOneBeforeAndAfterStatefulNodeMap(PageDepositorState) {
  n2t.EarlyReturnOneToOneBeforeAndAfterStatefulNodeMap(
    v_before_transforming_children: page_depositor_v_before,
    v_after_transforming_children: n2t.before_and_after_keep_latest_state,
    t_nodemap: n2t.before_and_after_identity,
  )
}

// ************************************************************
// at root: page-gathering followed by page-depositing
// ************************************************************

fn at_root(root: VXML) -> Result(VXML, DesugaringError) {
  use pages <- on.ok(gather_pages(root))

  let assert Ok(#(root, #(_, []))) =
    n2t.early_return_one_to_one_before_and_after_stateful_nodemap_traverse_tree(
      #([], pages),
      root,
      page_depositor_nodemap(),
    )

  Ok(root)
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

pub const name = "ti2_add_prev_next_chapter_title_elements"
fn desugarer_blame(line_no: Int) { bl.Des([], name, line_no) }

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// copies the title and number-chiron attrs
/// of the previous and next chapter/subchapter, if
/// any, and dumps these into 'PrevChapterOrSubTitle'
/// and 'NextChapterOrSubTitle' elements at the top
/// each chapter, 
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
                  <> Index
                  <> Chapter
                    <> ChapterTitle
                      number-chiron=1.
                      <>
                        \"Banana\"
                    <> Sub
                      <> SubTitle
                        number-chiron=1.1
                        <>
                          \"Green\"
                    <> Sub
                      <> SubTitle
                        number-chiron=1.2
                        <> b
                          <>
                            \"Fig\"
                        <>
                          \" Tree\"
                  <> Chapter
                    <> ChapterTitle
                      number-chiron=2.
                      <>
                        \"And\"
                    <> Sub
                      <> SubTitle
                        number-chiron=2.1
                        <>
                          \"Leaf\"
                    <> Sub
                      <> SubTitle
                        number-chiron=2.2
                        <>
                          \"Absolute\"
                    <> Sub
                      <> SubTitle
                        number-chiron=2.3
                        <>
                          \"Absolute\"
                          \" Tree\"
                  <> Chapter
                    <> ChapterTitle
                      number-chiron=3.
                      <>
                        \"And\"
                ",
      expected: "
                <> Document
                  <> Index
                    <> NextChapterOrSubTitle
                      ch_no=1
                      number-chiron=1.
                      <>
                        \"Banana\"
                  <> Chapter
                    <> NextChapterOrSubTitle
                      ch_no=1
                      sub_no=1
                      number-chiron=1.1
                      <>
                        \"Green\"
                    <> ChapterTitle
                      number-chiron=1.
                      <>
                        \"Banana\"
                    <> Sub
                      <> NextChapterOrSubTitle
                        ch_no=1
                        sub_no=2
                        number-chiron=1.2
                        <> b
                          <>
                            \"Fig\"
                        <>
                          \" Tree\"
                      <> PrevChapterOrSubTitle
                        ch_no=1
                        number-chiron=1.
                        <>
                          \"Banana\"
                      <> SubTitle
                        number-chiron=1.1
                        <>
                          \"Green\"
                    <> Sub
                      <> NextChapterOrSubTitle
                        ch_no=2
                        number-chiron=2.
                        <>
                          \"And\"
                      <> PrevChapterOrSubTitle
                        ch_no=1
                        sub_no=1
                        number-chiron=1.1
                        <>
                          \"Green\"
                      <> SubTitle
                        number-chiron=1.2
                        <> b
                          <>
                            \"Fig\"
                        <>
                          \" Tree\"
                  <> Chapter
                    <> NextChapterOrSubTitle
                      ch_no=2
                      sub_no=1
                      number-chiron=2.1
                      <>
                        \"Leaf\"
                    <> PrevChapterOrSubTitle
                      ch_no=1
                      sub_no=2
                      number-chiron=1.2
                      <> b
                        <>
                          \"Fig\"
                      <>
                        \" Tree\"
                    <> ChapterTitle
                      number-chiron=2.
                      <>
                        \"And\"
                    <> Sub
                      <> NextChapterOrSubTitle
                        ch_no=2
                        sub_no=2
                        number-chiron=2.2
                        <>
                          \"Absolute\"
                      <> PrevChapterOrSubTitle
                        ch_no=2
                        number-chiron=2.
                        <>
                          \"And\"
                      <> SubTitle
                        number-chiron=2.1
                        <>
                          \"Leaf\"
                    <> Sub
                      <> NextChapterOrSubTitle
                        ch_no=2
                        sub_no=3
                        number-chiron=2.3
                        <>
                          \"Absolute\"
                          \" Tree\"
                      <> PrevChapterOrSubTitle
                        ch_no=2
                        sub_no=1
                        number-chiron=2.1
                        <>
                          \"Leaf\"
                      <> SubTitle
                        number-chiron=2.2
                        <>
                          \"Absolute\"
                    <> Sub
                      <> NextChapterOrSubTitle
                        ch_no=3
                        number-chiron=3.
                        <>
                          \"And\"
                      <> PrevChapterOrSubTitle
                        ch_no=2
                        sub_no=2
                        number-chiron=2.2
                        <>
                          \"Absolute\"
                      <> SubTitle
                        number-chiron=2.3
                        <>
                          \"Absolute\"
                          \" Tree\"
                  <> Chapter
                    <> PrevChapterOrSubTitle
                      ch_no=2
                      sub_no=3
                      number-chiron=2.3
                      <>
                        \"Absolute\"
                        \" Tree\"
                    <> ChapterTitle
                      number-chiron=3.
                      <>
                        \"And\"
                "
    )
  ]
}

pub fn assertive_tests() {
  infra.assertive_test_collection_from_data_no_param(name, assertive_tests_data(), constructor)
}
