import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import infrastructure.{
  type Desugarer,
  type DesugaringError,
  type TrafficLight,
  Desugarer,
  Continue,
  GoBack,
} as infra
import vxml.{type VXML, Attr, V}
import nodemaps_2_desugarer_transforms as n2t
import blame as bl
import on

// ---- Page address types ----

type PageAddr {
  SectionAddr(ch_no: Int, sec_no: Int)
  SubSectionAddr(ch_no: Int, sec_no: Int, sub_no: Int)
}

fn page_href(addr: PageAddr) -> String {
  case addr {
    SectionAddr(ch, sec) ->
      "/" <> int.to_string(ch) <> "-" <> int.to_string(sec) <> ".html"
    SubSectionAddr(ch, sec, sub) ->
      "/"
      <> int.to_string(ch)
      <> "-"
      <> int.to_string(sec)
      <> "-"
      <> int.to_string(sub)
      <> ".html"
  }
}

// ---- Pass 1: Gather pages in order ----

type GatherState {
  GatherState(
    pages: List(PageAddr),
    ch_no: Int,
    sec_no: Int,
    sub_no: Int,
  )
}

fn gather_nodemap(
  vxml: VXML,
  state: GatherState,
) -> Result(#(GatherState, TrafficLight), DesugaringError) {
  case vxml {
    V(_, "Document", _, _) -> Ok(#(state, Continue))
    V(_, "Chapter", _, _) ->
      Ok(#(
        GatherState(..state, ch_no: state.ch_no + 1, sec_no: 0, sub_no: 0),
        Continue,
      ))
    V(_, "Section", _, _) -> {
      let new_sec = state.sec_no + 1
      let addr = SectionAddr(state.ch_no, new_sec)
      Ok(#(
        GatherState(
          ..state,
          sec_no: new_sec,
          sub_no: 0,
          pages: [addr, ..state.pages],
        ),
        Continue,
      ))
    }
    V(_, "SubSection", _, _) -> {
      let new_sub = state.sub_no + 1
      let addr = SubSectionAddr(state.ch_no, state.sec_no, new_sub)
      Ok(#(
        GatherState(..state, sub_no: new_sub, pages: [addr, ..state.pages]),
        GoBack,
      ))
    }
    _ -> Ok(#(state, GoBack))
  }
}

fn gather_pages(root: VXML) -> Result(List(PageAddr), DesugaringError) {
  use final_state <- on.ok(
    n2t.early_return_identity_stateful_walk(
      root,
      GatherState(pages: [], ch_no: 0, sec_no: 0, sub_no: 0),
      gather_nodemap,
    ),
  )
  Ok(list.reverse(final_state.pages))
}

// ---- Build nav dict ----

fn build_nav_entries(
  pages: List(PageAddr),
  hrefs: List(String),
  prev_href: Option(String),
) -> List(#(PageAddr, #(Option(String), Option(String)))) {
  case pages, hrefs {
    [], _ -> []
    [page, ..rest_pages], [href, ..rest_hrefs] -> {
      let next_href = case rest_hrefs {
        [] -> None
        [next, ..] -> Some(next)
      }
      [
        #(page, #(prev_href, next_href)),
        ..build_nav_entries(rest_pages, rest_hrefs, Some(href))
      ]
    }
    _, _ -> []
  }
}

fn build_nav_dict(
  pages: List(PageAddr),
) -> Dict(PageAddr, #(Option(String), Option(String))) {
  let hrefs = list.map(pages, page_href)
  build_nav_entries(pages, hrefs, None)
  |> dict.from_list
}

// ---- Navigation node construction ----

fn anchor(class: String, href: String) -> VXML {
  let b = desugarer_blame(120)
  V(b, "a", [Attr(b, "class", class), Attr(b, "href", href)], [])
}

fn make_navigation(
  prev_href: Option(String),
  next_href: Option(String),
) -> VXML {
  let b = desugarer_blame(128)
  let links =
    [
      prev_href |> option.map(fn(h) { anchor("prev-page", h) }),
      next_href |> option.map(fn(h) { anchor("next-page", h) }),
    ]
    |> option.values
  V(b, "Navigation", [Attr(b, "class", "nav")], links)
}

// ---- Pass 2: Transform ----

// state = (ch_no, sec_no, sub_no) — all start at 0
type TransformState =
  #(Int, Int, Int)

fn v_before(
  nav_dict: Dict(PageAddr, #(Option(String), Option(String))),
  node: VXML,
  state: TransformState,
) -> #(VXML, TransformState) {
  let #(ch, sec, sub) = state
  case node {
    V(_, "Document", _, _) -> #(node, state)
    V(_, "Chapter", _, _) -> #(node, #(ch + 1, 0, 0))
    V(_, "Section", _, _) -> {
      let new_sec = sec + 1
      let addr = SectionAddr(ch, new_sec)
      let #(prev_href, next_href) =
        result.unwrap(dict.get(nav_dict, addr), #(None, None))
      let nav = make_navigation(prev_href, next_href)
      #(infra.v_prepend_child(node, nav), #(ch, new_sec, 0))
    }
    V(_, "SubSection", _, _) -> {
      let new_sub = sub + 1
      let addr = SubSectionAddr(ch, sec, new_sub)
      let #(prev_href, next_href) =
        result.unwrap(dict.get(nav_dict, addr), #(None, None))
      let nav = make_navigation(prev_href, next_href)
      #(infra.v_prepend_child(node, nav), #(ch, sec, new_sub))
    }
    _ -> #(node, state)
  }
}

fn at_root(root: VXML) -> Result(VXML, DesugaringError) {
  use pages <- on.ok(gather_pages(root))
  let nav_dict = build_nav_dict(pages)
  let nm =
    n2t.OneToOneNoErrorBeforeAndAfterStatefulNodemap(
      v_before_transforming_children: fn(v, s) { v_before(nav_dict, v, s) },
      v_after_transforming_children: fn(v, _, latest) { #(v, latest) },
      t_nodemap: fn(v, s) { #(v, s) },
    )
  let transform =
    n2t.one_to_one_no_error_before_and_after_stateful_nodemap_2_desugarer_transform(
      nm,
      #(0, 0, 0),
    )
  use #(vxml, _) <- on.ok(transform(root))
  Ok(vxml)
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

pub const name = "dr_create_menu"

fn desugarer_blame(line_no: Int) {
  bl.Des([], name, line_no)
}

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// generate Navigation nodes with prev-page and next-page
/// anchor links for Section and SubSection pages.
/// Chapter pages do not get Navigation nodes.
/// Pages are ordered linearly: sections within chapters,
/// subsections within sections, across chapters in document
/// order.
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
      source: "
                <> Document
                  <> Chapter
                    <> Section
                    <> Section
                ",
      expected: "
                <> Document
                  <> Chapter
                    <> Section
                      <> Navigation
                        class=nav
                        <> a
                          class=next-page
                          href=/1-2.html
                    <> Section
                      <> Navigation
                        class=nav
                        <> a
                          class=prev-page
                          href=/1-1.html
                ",
    ),
    infra.AssertiveTestDataNoParam(
      source: "
                <> Document
                  <> Chapter
                    <> Section
                    <> Section
                  <> Chapter
                    <> Section
                    <> Section
                      <> SubSection
                      <> SubSection
                      <> SubSection
                  <> Chapter
                    <> Section
                ",
      expected: "
                <> Document
                  <> Chapter
                    <> Section
                      <> Navigation
                        class=nav
                        <> a
                          class=next-page
                          href=/1-2.html
                    <> Section
                      <> Navigation
                        class=nav
                        <> a
                          class=prev-page
                          href=/1-1.html
                        <> a
                          class=next-page
                          href=/2-1.html
                  <> Chapter
                    <> Section
                      <> Navigation
                        class=nav
                        <> a
                          class=prev-page
                          href=/1-2.html
                        <> a
                          class=next-page
                          href=/2-2.html
                    <> Section
                      <> Navigation
                        class=nav
                        <> a
                          class=prev-page
                          href=/2-1.html
                        <> a
                          class=next-page
                          href=/2-2-1.html
                      <> SubSection
                        <> Navigation
                          class=nav
                          <> a
                            class=prev-page
                            href=/2-2.html
                          <> a
                            class=next-page
                            href=/2-2-2.html
                      <> SubSection
                        <> Navigation
                          class=nav
                          <> a
                            class=prev-page
                            href=/2-2-1.html
                          <> a
                            class=next-page
                            href=/2-2-3.html
                      <> SubSection
                        <> Navigation
                          class=nav
                          <> a
                            class=prev-page
                            href=/2-2-2.html
                          <> a
                            class=next-page
                            href=/3-1.html
                  <> Chapter
                    <> Section
                      <> Navigation
                        class=nav
                        <> a
                          class=prev-page
                          href=/2-2-3.html
                ",
    ),
  ]
}

pub fn assertive_tests() {
  infra.assertive_test_collection_from_data_no_param(
    name,
    assertive_tests_data(),
    constructor,
  )
}
