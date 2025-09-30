import gleam/list
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
  Attribute,
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

fn gather_title(
  vxml: VXML,
  tag: String,
) -> Result(Title, DesugaringError) {
  use title_element <- on.ok(infra.v_unique_child(vxml, tag))
  let assert V(_, _, _, title) = title_element
  Ok(title)
}

fn gather_chiron(
  vxml: VXML,
) -> Result(String, DesugaringError) {
  let assert V(blame, _, attrs, _) = vxml
  infra.attributes_value_of_unique_key(attrs, "number-chiron", blame)
}

fn page_gatherer_v_before(
  vxml: VXML,
  state: PageGatheringState,
) -> Result(#(VXML, PageGatheringState, TrafficLight), DesugaringError) {
  case vxml {
    V(_, "Document", _, _) -> Ok(#(vxml, state, Continue))
    V(_, "Chapter", _, _) -> {
      let PageGatheringState(pages, ch_no, _) = state
      let ch_no = ch_no + 1
      use title <- on.ok(gather_title(vxml, "ChapterTitle"))
      use chiron <- on.ok(gather_chiron(vxml))
      let pages = [Chapter(title, chiron, ch_no), ..pages]
      let state = PageGatheringState(pages, ch_no, 0)
      Ok(#(vxml, state, Continue))
    }
    V(_, "Sub", _, _) -> {
      let PageGatheringState(pages, ch_no, sub_no) = state
      let sub_no = sub_no + 1
      use title <- on.ok(gather_title(vxml, "SubTitle"))
      use chiron <- on.ok(gather_chiron(vxml))
      let pages = [Sub(title, chiron, ch_no, sub_no), ..pages]
      let state = PageGatheringState(pages, ch_no, sub_no)
      Ok(#(vxml, state, GoBack))
    }
    _ -> Ok(#(vxml, state, GoBack))
  }
}

fn page_gatherer_v_after(
  vxml: VXML, 
  _: PageGatheringState,
  state: PageGatheringState,
) -> Result(#(VXML, PageGatheringState), DesugaringError) {
  Ok(#(vxml, state))
}

fn page_gatherer_t(
  vxml: VXML, 
  state: PageGatheringState,
) -> Result(#(VXML, PageGatheringState), DesugaringError) {
  Ok(#(vxml, state))
}

fn page_gatherer_nodemap() -> n2t.EarlyReturnOneToOneBeforeAndAfterStatefulNodeMap(PageGatheringState) {
  n2t.EarlyReturnOneToOneBeforeAndAfterStatefulNodeMap(
    v_before_transforming_children: page_gatherer_v_before,
    v_after_transforming_children: page_gatherer_v_after,
    t_nodemap: page_gatherer_t,
  )
}

// ************************************************************
// PAGE DEPOSITING: walking the tree with Pages in hand to
// write the appropriate title elements to each page
// ************************************************************

type PageDepositorState = #(List(Page), List(Page))

fn deposit_next_page(
  vxml: VXML,
  next: Option(Page),
) -> VXML {
  let assert V(_, _, _, children) = vxml
  use next <- on.none_some(next, vxml)
  let title = V(
    desugarer_blame(124),
    "NextChapterOrSubTitle",
    [
      Attribute(desugarer_blame(127), "number-chiron", next.number_chiron),
    ],
    next.title,
  )
  V(..vxml, children: [title, ..children])
}

fn deposit_prev_page(
  vxml: VXML,
  prev: Option(Page),
) -> VXML {
  let assert V(_, _, _, children) = vxml
  use prev <- on.none_some(prev, vxml)
  let title = V(
    desugarer_blame(141),
    "PrevChapterOrSubTitle",
    [
      Attribute(desugarer_blame(144), "number-chiron", prev.number_chiron),
    ],
    prev.title,
  )
  V(..vxml, children: [title, ..children])
}

fn next_prev_pages(
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
    V(_, "Chapter", _, _) -> {
      let #(previous, upcoming) = state
      let #(prev, this, next, upcoming) = next_prev_pages(previous, upcoming, Chapter([], "", 0))
      let vxml = vxml |> deposit_prev_page(prev) |> deposit_next_page(next)
      Ok(#(vxml, #([this, ..previous], upcoming), Continue))
    }
    V(_, "Sub", _, _) -> {
      let #(previous, upcoming) = state
      let #(prev, this, next, upcoming) = next_prev_pages(previous, upcoming, Sub([], "", 0, 0))
      let vxml = vxml |> deposit_prev_page(prev) |> deposit_next_page(next)
      Ok(#(vxml, #([this, ..previous], upcoming), GoBack))
    }
    _ -> Ok(#(vxml, state, GoBack))
  }
}

fn page_depositor_v_after(
  vxml: VXML, 
  _: PageDepositorState,
  state: PageDepositorState,
) -> Result(#(VXML, PageDepositorState), DesugaringError) {
  Ok(#(vxml, state))
}

fn page_depositor_t(
  vxml: VXML, 
  state: PageDepositorState,
) -> Result(#(VXML, PageDepositorState), DesugaringError) {
  Ok(#(vxml, state))
}

fn page_depositor_nodemap() -> n2t.EarlyReturnOneToOneBeforeAndAfterStatefulNodeMap(PageDepositorState) {
  n2t.EarlyReturnOneToOneBeforeAndAfterStatefulNodeMap(
    v_before_transforming_children: page_depositor_v_before,
    v_after_transforming_children: page_depositor_v_after,
    t_nodemap: page_depositor_t,
  )
}

// ************************************************************
// at root: page-gathering followed by page-depositing
// ************************************************************

fn at_root(root: VXML) -> Result(VXML, DesugaringError) {
  use #(_, page_gathering_state) <- on.ok(
    n2t.early_return_one_to_one_before_and_after_stateful_nodemap_recursive_application(
      PageGatheringState([], 0, 0),
      root,
      page_gatherer_nodemap(),
    )
  )

  let pages = page_gathering_state.pages |> list.reverse

  let assert Ok(#(root, #(_, []))) =
    n2t.early_return_one_to_one_before_and_after_stateful_nodemap_recursive_application(
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
/// copies the title and number-chiron attributes
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
                  <> Chapter
                    number-chiron=1.
                    <> ChapterTitle
                      <>
                        \"Banana\"
                    <> Sub
                      number-chiron=1.1
                      <> SubTitle
                        <>
                          \"Green\"
                    <> Sub
                      number-chiron=1.2
                      <> SubTitle
                        <> b
                          <>
                            \"Fig\"
                        <>
                          \" Tree\"
                  <> Chapter
                    number-chiron=2.
                    <> ChapterTitle
                      <>
                        \"And\"
                    <> Sub
                      number-chiron=2.1
                      <> SubTitle
                        <>
                          \"Leaf\"
                    <> Sub
                      number-chiron=2.2
                      <> SubTitle
                        <>
                          \"Absolute\"
                    <> Sub
                      number-chiron=2.2
                      <> SubTitle
                        <>
                          \"Absolute\"
                          \" Tree\"
                  <> Chapter
                    number-chiron=3.
                    <> ChapterTitle
                      <>
                        \"And\"
                ",
      expected: "
                <> Document
                  <> Chapter
                    number-chiron=1.
                    <> NextChapterOrSubTitle
                      number-chiron=1.1
                      <>
                        \"Green\"
                    <> ChapterTitle
                      <>
                        \"Banana\"
                    <> Sub
                      number-chiron=1.1
                      <> NextChapterOrSubTitle
                        number-chiron=1.2
                        <> b
                          <>
                            \"Fig\"
                        <>
                          \" Tree\"
                      <> PrevChapterOrSubTitle
                        number-chiron=1.
                        <>
                          \"Banana\"
                      <> SubTitle
                        <>
                          \"Green\"
                    <> Sub
                      number-chiron=1.2
                      <> NextChapterOrSubTitle
                        number-chiron=2.
                        <>
                          \"And\"
                      <> PrevChapterOrSubTitle
                        number-chiron=1.1
                        <>
                          \"Green\"
                      <> SubTitle
                        <> b
                          <>
                            \"Fig\"
                        <>
                          \" Tree\"
                  <> Chapter
                    number-chiron=2.
                    <> NextChapterOrSubTitle
                      number-chiron=2.1
                      <>
                        \"Leaf\"
                    <> PrevChapterOrSubTitle
                      number-chiron=1.2
                      <> b
                        <>
                          \"Fig\"
                      <>
                        \" Tree\"
                    <> ChapterTitle
                      <>
                        \"And\"
                    <> Sub
                      number-chiron=2.1
                      <> NextChapterOrSubTitle
                        number-chiron=2.2
                        <>
                          \"Absolute\"
                      <> PrevChapterOrSubTitle
                        number-chiron=2.
                        <>
                          \"And\"
                      <> SubTitle
                        <>
                          \"Leaf\"
                    <> Sub
                      number-chiron=2.2
                      <> NextChapterOrSubTitle
                        number-chiron=2.2
                        <>
                          \"Absolute\"
                          \" Tree\"
                      <> PrevChapterOrSubTitle
                        number-chiron=2.1
                        <>
                          \"Leaf\"
                      <> SubTitle
                        <>
                          \"Absolute\"
                    <> Sub
                      number-chiron=2.2
                      <> NextChapterOrSubTitle
                        number-chiron=3.
                        <>
                          \"And\"
                      <> PrevChapterOrSubTitle
                        number-chiron=2.2
                        <>
                          \"Absolute\"
                      <> SubTitle
                        <>
                          \"Absolute\"
                          \" Tree\"
                  <> Chapter
                    number-chiron=3.
                    <> PrevChapterOrSubTitle
                      number-chiron=2.2
                      <>
                        \"Absolute\"
                        \" Tree\"
                    <> ChapterTitle
                      <>
                        \"And\"
                "
    )
  ]
}

pub fn assertive_tests() {
  infra.assertive_test_collection_from_data_no_param(name, assertive_tests_data(), constructor)
}
