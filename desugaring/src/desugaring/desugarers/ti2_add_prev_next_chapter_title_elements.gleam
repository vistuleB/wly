import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugaringError, type TrafficLight, Continue, GoBack,
}
import desugaring/nodemaps_2_transform as n2t
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string.{inspect as ins}
import on
import vxml.{type Attr, type VXML, Attr, V}
import vxml/blame as bl

pub const name = "ti2_add_prev_next_chapter_title_elements"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Adds previous and next chapter or subchapter title
/// elements to each navigable page.
pub fn constructor() -> Desugarer {
  authoring.no_param_desugarer(
    name: name,
    transform: inner_param_to_transform(),
  )
}

// ************************************************************
// common types
// ************************************************************

type Title =
  List(VXML)

type Page {
  Chapter(title: Title, number_chiron: String, ch_no: Int)
  Sub(title: Title, number_chiron: String, ch_no: Int, sub_no: Int)
}

// ************************************************************
// PAGE GATHERING: walking the tree to construct a List(Page)
// ************************************************************

type PageGatheringState {
  PageGatheringState(pages: List(Page), ch_no: Int, sub_no: Int)
}

fn gather_title_and_chiron(
  vxml: VXML,
  tag: String,
) -> Result(#(Title, String), DesugaringError) {
  use title_element <- on.ok(core.v_unique_child(vxml, tag))
  let assert V(blame, _, attrs, title) = title_element
  // so that we can stomach both the cases where the
  // title has already been wrapped in <p></p> or not:
  let title = case title {
    [V(_, "p", _, title)] -> title
    _ -> title
  }
  use chiron <- on.ok(core.attrs_val_of_unique_key(
    attrs,
    "number-chiron",
    blame,
  ))
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

fn page_information_collector(
  vxml: VXML,
  state: PageGatheringState,
) -> Result(#(PageGatheringState, TrafficLight), DesugaringError) {
  case vxml {
    V(_, "Document", _, _) -> Ok(#(state, Continue))

    V(_, "Chapter", _, _) -> {
      use #(title, chiron) <- on.ok(gather_title_and_chiron(
        vxml,
        "ChapterTitle",
      ))
      Ok(#(
        state |> add_chapter_to_page_gathering_state(title, chiron),
        Continue,
      ))
    }

    V(_, "Sub", _, _) -> {
      use #(title, chiron) <- on.ok(gather_title_and_chiron(vxml, "SubTitle"))
      Ok(#(state |> add_sub_to_page_gathering_state(title, chiron), GoBack))
    }

    _ -> Ok(#(state, GoBack))
  }
}

fn gather_pages(root: VXML) -> Result(List(Page), DesugaringError) {
  use PageGatheringState(pages, _, _) <- on.ok(n2t.early_return_stateful_visit(
    root,
    PageGatheringState([], 0, 0),
    page_information_collector,
  ))

  pages |> list.reverse |> Ok
}

// ************************************************************
// PAGE DEPOSITING: walking the tree with Pages in hand to
// write the appropriate title elements to each page
// ************************************************************

type PageDepositorState =
  #(List(Page), List(Page))

fn attrs_4_page(page: Page) -> List(Attr) {
  case page {
    Chapter(_, number_chiron, ch_no) -> [
      Attr(desugarer_blame(136), "ch_no", ins(ch_no)),
      Attr(desugarer_blame(137), "number-chiron", number_chiron),
    ]
    Sub(_, number_chiron, ch_no, sub_no) -> [
      Attr(desugarer_blame(140), "ch_no", ins(ch_no)),
      Attr(desugarer_blame(141), "sub_no", ins(sub_no)),
      Attr(desugarer_blame(142), "number-chiron", number_chiron),
    ]
  }
}

fn deposit_next(vxml: VXML, next: Option(Page)) -> VXML {
  let assert V(_, _, _, children) = vxml
  use next <- on.eager_none_some(next, vxml)
  let title =
    V(
      desugarer_blame(152),
      "NextChapterOrSubTitle",
      attrs_4_page(next),
      next.title,
    )
  V(..vxml, children: [title, ..children])
}

fn deposit_prev(vxml: VXML, prev: Option(Page)) -> VXML {
  let assert V(_, _, _, children) = vxml
  use prev <- on.eager_none_some(prev, vxml)
  let title =
    V(
      desugarer_blame(165),
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
  let _ = case expecting {
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
      let #(prev, this, next, upcoming) =
        prev_this_next_rest(previous, upcoming, Chapter([], "", 0))
      let vxml = vxml |> deposit_prev(prev) |> deposit_next(next)
      Ok(#(vxml, #([this, ..previous], upcoming), Continue))
    }
    V(_, "Sub", _, _) -> {
      let #(previous, upcoming) = state
      let #(prev, this, next, upcoming) =
        prev_this_next_rest(previous, upcoming, Sub([], "", 0, 0))
      let vxml = vxml |> deposit_prev(prev) |> deposit_next(next)
      Ok(#(vxml, #([this, ..previous], upcoming), GoBack))
    }
    _ -> Ok(#(vxml, state, GoBack))
  }
}

fn page_depositor_nodemap() -> n2t.EarlyReturnOneToOneEnterExitStatefulNodemap(
  PageDepositorState,
) {
  n2t.EarlyReturnOneToOneEnterExitStatefulNodemap(
    on_enter: page_depositor_v_before,
    on_exit: n2t.enter_exit_keep_latest_state,
    on_text: n2t.enter_exit_identity,
  )
}

// ************************************************************
// at root: page-gathering followed by page-depositing
// ************************************************************

fn at_root(root: VXML) -> Result(VXML, DesugaringError) {
  use pages <- on.ok(gather_pages(root))

  let assert Ok(#(root, #(_, []))) =
    n2t.early_return_one_to_one_enter_exit_stateful_nodemap_walk(
      #([], pages),
      root,
      page_depositor_nodemap(),
    )

  Ok(root)
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
                  <> Index
                  <> Chapter
                    <> ChapterTitle
                      number-chiron=1.
                      <>
                        'Banana'
                    <> Sub
                      <> SubTitle
                        number-chiron=1.1
                        <>
                          'Green'
                    <> Sub
                      <> SubTitle
                        number-chiron=1.2
                        <> b
                          <>
                            'Fig'
                        <>
                          ' Tree'
                  <> Chapter
                    <> ChapterTitle
                      number-chiron=2.
                      <>
                        'And'
                    <> Sub
                      <> SubTitle
                        number-chiron=2.1
                        <>
                          'Leaf'
                    <> Sub
                      <> SubTitle
                        number-chiron=2.2
                        <>
                          'Absolute'
                    <> Sub
                      <> SubTitle
                        number-chiron=2.3
                        <>
                          'Absolute'
                          ' Tree'
                  <> Chapter
                    <> ChapterTitle
                      number-chiron=3.
                      <>
                        'And'
                ",
      expected: "
                <> Document
                  <> Index
                    <> NextChapterOrSubTitle
                      ch_no=1
                      number-chiron=1.
                      <>
                        'Banana'
                  <> Chapter
                    <> NextChapterOrSubTitle
                      ch_no=1
                      sub_no=1
                      number-chiron=1.1
                      <>
                        'Green'
                    <> ChapterTitle
                      number-chiron=1.
                      <>
                        'Banana'
                    <> Sub
                      <> NextChapterOrSubTitle
                        ch_no=1
                        sub_no=2
                        number-chiron=1.2
                        <> b
                          <>
                            'Fig'
                        <>
                          ' Tree'
                      <> PrevChapterOrSubTitle
                        ch_no=1
                        number-chiron=1.
                        <>
                          'Banana'
                      <> SubTitle
                        number-chiron=1.1
                        <>
                          'Green'
                    <> Sub
                      <> NextChapterOrSubTitle
                        ch_no=2
                        number-chiron=2.
                        <>
                          'And'
                      <> PrevChapterOrSubTitle
                        ch_no=1
                        sub_no=1
                        number-chiron=1.1
                        <>
                          'Green'
                      <> SubTitle
                        number-chiron=1.2
                        <> b
                          <>
                            'Fig'
                        <>
                          ' Tree'
                  <> Chapter
                    <> NextChapterOrSubTitle
                      ch_no=2
                      sub_no=1
                      number-chiron=2.1
                      <>
                        'Leaf'
                    <> PrevChapterOrSubTitle
                      ch_no=1
                      sub_no=2
                      number-chiron=1.2
                      <> b
                        <>
                          'Fig'
                      <>
                        ' Tree'
                    <> ChapterTitle
                      number-chiron=2.
                      <>
                        'And'
                    <> Sub
                      <> NextChapterOrSubTitle
                        ch_no=2
                        sub_no=2
                        number-chiron=2.2
                        <>
                          'Absolute'
                      <> PrevChapterOrSubTitle
                        ch_no=2
                        number-chiron=2.
                        <>
                          'And'
                      <> SubTitle
                        number-chiron=2.1
                        <>
                          'Leaf'
                    <> Sub
                      <> NextChapterOrSubTitle
                        ch_no=2
                        sub_no=3
                        number-chiron=2.3
                        <>
                          'Absolute'
                          ' Tree'
                      <> PrevChapterOrSubTitle
                        ch_no=2
                        sub_no=1
                        number-chiron=2.1
                        <>
                          'Leaf'
                      <> SubTitle
                        number-chiron=2.2
                        <>
                          'Absolute'
                    <> Sub
                      <> NextChapterOrSubTitle
                        ch_no=3
                        number-chiron=3.
                        <>
                          'And'
                      <> PrevChapterOrSubTitle
                        ch_no=2
                        sub_no=2
                        number-chiron=2.2
                        <>
                          'Absolute'
                      <> SubTitle
                        number-chiron=2.3
                        <>
                          'Absolute'
                          ' Tree'
                  <> Chapter
                    <> PrevChapterOrSubTitle
                      ch_no=2
                      sub_no=3
                      number-chiron=2.3
                      <>
                        'Absolute'
                        ' Tree'
                    <> ChapterTitle
                      number-chiron=3.
                      <>
                        'And'
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
