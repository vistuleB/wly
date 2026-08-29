import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugaringError, type TrafficLight, Continue,
  DesugaringError, GoBack,
}
import desugaring/nodemaps_2_transform as n2t
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string.{inspect as ins}
import on
import vxml.{type Attr, type VXML, Attr, Line, T, V}
import vxml/blame as bl

pub const name = "ti2_create_menu"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Generates ti2 navigation menus from previously created
/// index and neighboring-page title elements.
pub fn constructor() -> Desugarer {
  authoring.no_param_desugarer(
    name: name,
    transform: inner_param_to_transform(),
  )
}

const prev_page_id_attr = Attr(bl.Des([], name, 31), "id", "prev-page")

const next_page_id_attr = Attr(bl.Des([], name, 33), "id", "next-page")

const hr_id_attr = Attr(bl.Des([], name, 35), "id", "bottom-menu-hr")

const hr = V(bl.Des([], name, 37), "hr", [hr_id_attr], [])

type Title =
  List(VXML)

type Page {
  Chapter(title: Title, number_chiron: String, ch_no: Int)
  Sub(title: Title, number_chiron: String, ch_no: Int, sub_no: Int)
}

type Relation {
  Prev
  Next
}

type ConstructedAtRootData {
  ConstructedAtRootData(
    chapter_word: String,
    toc_word: String,
    homepage_word: String,
    homepage_url: String,
  )
}

type LinkData {
  LinkData(
    at_root_data: ConstructedAtRootData,
    index: Option(String),
    prev: Option(Page),
    next: Option(Page),
  )
}

type Menu {
  Top
  Bottom
}

fn attribute(key: String, value: String) -> Attr {
  Attr(desugarer_blame(76), key, value)
}

fn string_to_text_node(content: String) -> VXML {
  T(desugarer_blame(80), [Line(desugarer_blame(80), content)])
}

fn homepage_link(at_root_data: ConstructedAtRootData) -> Option(VXML) {
  case at_root_data.homepage_url {
    "" -> None
    url ->
      Some(
        V(desugarer_blame(88), "a", [attribute("href", url)], [
          string_to_text_node(at_root_data.homepage_word),
        ]),
      )
  }
}

fn index_link(toc_word: String) -> VXML {
  V(desugarer_blame(96), "a", [attribute("href", "./index.html")], [
    V(desugarer_blame(97), "span", [attribute("class", "inhalts_arrows")], [
      string_to_text_node("<< "),
    ]),
    string_to_text_node(toc_word),
  ])
}

fn page_href(page: Page) -> String {
  case page {
    Chapter(_, _, ch_no) -> "./" <> ins(ch_no) <> "-0.html"
    Sub(_, _, ch_no, sub_no) ->
      "./" <> ins(ch_no) <> "-" <> ins(sub_no) <> ".html"
  }
}

fn tooltip(page: Page, relation: Relation, which: Menu) -> VXML {
  let p1 = case which {
    Top -> "top-"
    Bottom -> "bottom-"
  }

  let p2 = case relation {
    Prev -> "prev-"
    Next -> "next-"
  }

  V(
    desugarer_blame(124),
    "span",
    [
      attribute("style", "visibility:hidden"),
      attribute("id", p1 <> p2 <> "page-tooltip"),
    ],
    page.title,
  )
}

fn page_link(
  page: Page,
  relation: Relation,
  which: Menu,
  chapter_word: String,
) -> VXML {
  let href_attr =
    page
    |> page_href
    |> attribute("href", _)

  let #(prev_prefix, next_suffix) = case relation {
    Prev -> #("<< ", "")
    Next -> #("", " >>")
  }

  let content = case page {
    Chapter(_, _, ch_no) ->
      prev_prefix <> chapter_word <> " " <> ins(ch_no) <> next_suffix
    Sub(_, _, ch_no, sub_no) ->
      prev_prefix
      <> chapter_word
      <> " "
      <> ins(ch_no)
      <> "."
      <> ins(sub_no)
      <> next_suffix
  }

  V(desugarer_blame(163), "a", [href_attr], [
    string_to_text_node(content),
    tooltip(page, relation, which),
  ])
}

fn menu_from_link_rows(
  row1: #(Option(VXML), Option(VXML)),
  row2: #(Option(VXML), Option(VXML)),
  which: Menu,
) -> VXML {
  let #(tag, p1) = case which {
    Top -> #("TopMenu", "top-")
    Bottom -> #("BottomMenu", "bottom-")
  }
  let dummy =
    V(
      desugarer_blame(180),
      "a",
      [attribute("class", "menu-row-placeholder")],
      [],
    )
  let row_constructor = fn(row: #(Option(VXML), Option(VXML))) {
    let #(left, right) = row
    let right = case right {
      None -> None
      Some(x) -> Some(core.v_append_classes(x, "menu-row-right"))
    }
    case left, right {
      None, None -> None
      _, _ -> {
        let left = option.unwrap(left, dummy)
        let right = option.unwrap(right, dummy)
        Some(
          V(desugarer_blame(197), "MenuRow", [attribute("class", "menu-row")], [
            left,
            right,
          ]),
        )
      }
    }
  }
  V(
    desugarer_blame(206),
    tag,
    [attribute("id", p1 <> "menu")],
    [row1, row2] |> list.map(row_constructor) |> option.values,
  )
}

fn menu_from_link_data(data: LinkData, which: Menu) -> VXML {
  let chapter_word = data.at_root_data.chapter_word
  let toc_word = data.at_root_data.toc_word
  let homepage = homepage_link(data.at_root_data)

  case data.index {
    // the Index
    None ->
      case which {
        Top ->
          menu_from_link_rows(
            #(
              homepage,
              data.next
                |> option.map(page_link(_, Next, which, chapter_word))
                |> option.map(core.v_prepend_attr(_, next_page_id_attr)),
            ),
            #(None, None),
            which,
          )

        Bottom -> menu_from_link_rows(#(None, None), #(None, None), which)
      }

    // a chapter or subchapter
    _ ->
      case which {
        Top ->
          menu_from_link_rows(
            #(
              case data.prev {
                None ->
                  index_link(toc_word) |> core.v_prepend_attr(prev_page_id_attr)
                _ -> index_link(toc_word)
              }
                |> Some,
              homepage,
            ),
            #(
              data.prev
                |> option.map(page_link(_, Prev, which, chapter_word))
                |> option.map(core.v_prepend_attr(_, prev_page_id_attr)),
              data.next
                |> option.map(page_link(_, Next, which, chapter_word))
                |> option.map(core.v_prepend_attr(_, next_page_id_attr)),
            ),
            which,
          )

        Bottom ->
          menu_from_link_rows(
            #(
              data.prev |> option.map(page_link(_, Prev, which, chapter_word)),
              data.next |> option.map(page_link(_, Next, which, chapter_word)),
            ),
            #(None, None),
            which,
          )
      }
  }
}

fn parse_page_number(
  blame: bl.Blame,
  key: String,
  value: String,
) -> Result(Int, DesugaringError) {
  int.parse(value)
  |> result.map_error(fn(_) {
    DesugaringError(
      blame,
      "cannot parse '" <> key <> "' attribute as an integer: " <> value,
    )
  })
}

fn page_from_title(
  vxml: VXML,
  relation: Relation,
) -> Result(Option(Page), DesugaringError) {
  let title_tag = case relation {
    Prev -> "PrevChapterOrSubTitle"
    Next -> "NextChapterOrSubTitle"
  }
  use title <- on.eager_none_some(
    core.v_first_child_with_tag(vxml, title_tag),
    Ok(None),
  )
  let assert V(blame, _, attrs, title) = title
  use chiron <- on.ok(core.attrs_val_of_unique_key(
    attrs,
    "number-chiron",
    blame,
  ))
  use ch_no <- on.ok(core.attrs_val_of_unique_key(attrs, "ch_no", blame))
  use ch_no <- on.ok(parse_page_number(blame, "ch_no", ch_no))
  let sub_no = case core.attrs_val_of_unique_key(attrs, "sub_no", blame) {
    Ok(x) -> {
      use x <- on.ok(parse_page_number(blame, "sub_no", x))
      Ok(Some(x))
    }
    _ -> Ok(None)
  }
  use sub_no <- on.ok(sub_no)
  let page = case sub_no {
    None -> Chapter(title, chiron, ch_no)
    Some(sub_no) -> Sub(title, chiron, ch_no, sub_no)
  }
  Ok(Some(page))
}

fn link_data_at_index(
  index: VXML,
  at_root_data: ConstructedAtRootData,
) -> Result(LinkData, DesugaringError) {
  use next <- on.ok(page_from_title(index, Next))
  case next {
    None ->
      Error(DesugaringError(
        bl.no_blame,
        "Index is missing a NextChapterOrSubTitle child",
      ))
    _ -> Ok(LinkData(at_root_data, None, None, next))
  }
}

fn link_data_at_ch_or_sub(
  vxml: VXML,
  at_root_data: ConstructedAtRootData,
) -> Result(LinkData, DesugaringError) {
  use prev <- on.ok(page_from_title(vxml, Prev))
  use next <- on.ok(page_from_title(vxml, Next))
  Ok(LinkData(at_root_data, Some("./index.html"), prev, next))
}

fn add_menu(node: VXML, data: LinkData, which: Menu) -> VXML {
  let menu = menu_from_link_data(data, which)
  case which {
    Top -> core.v_prepend_child(node, menu)
    Bottom -> core.v_pour_before_first(node, [menu, hr], "Sub")
  }
}

fn nodemap(
  vxml: VXML,
  at_root_data: ConstructedAtRootData,
) -> Result(#(VXML, TrafficLight), DesugaringError) {
  use #(data, continue) <- on.ok(case vxml {
    V(_, "Index", _, _) -> {
      use data <- on.ok(link_data_at_index(vxml, at_root_data))
      Ok(#(Some(data), GoBack))
    }

    V(_, "Chapter", _, _) -> {
      use data <- on.ok(link_data_at_ch_or_sub(vxml, at_root_data))
      Ok(#(Some(data), Continue))
    }

    V(_, "Sub", _, _) -> {
      use data <- on.ok(link_data_at_ch_or_sub(vxml, at_root_data))
      Ok(#(Some(data), GoBack))
    }

    V(_, "Document", _, _) -> {
      Ok(#(None, Continue))
    }

    _ -> {
      Ok(#(None, GoBack))
    }
  })

  let vxml = case data {
    None -> vxml
    Some(data) -> {
      case data.index {
        None -> vxml |> add_menu(data, Top)
        // the index gets no bottom menu
        Some(_) -> vxml |> add_menu(data, Top) |> add_menu(data, Bottom)
      }
    }
  }

  Ok(#(vxml, continue))
}

fn at_root(root: VXML) -> Result(VXML, DesugaringError) {
  let homepage_url =
    core.v_val_of_first_attr_with_key(root, "homepage")
    |> option.unwrap("")

  use language <- on.ok(
    case core.v_val_of_first_attr_with_key(root, "language") {
      None ->
        Error(DesugaringError(
          bl.no_blame,
          "ti2_create_menu: missing 'language' attribute on document root",
        ))
      Some(lang) -> Ok(lang)
    },
  )

  use at_root_data <- on.ok(case language {
    "de" ->
      Ok(ConstructedAtRootData(
        chapter_word: "Kapitel",
        toc_word: "Inhaltsverzeichnis",
        homepage_word: "zur Kursübersicht",
        homepage_url: homepage_url,
      ))
    "en" ->
      Ok(ConstructedAtRootData(
        chapter_word: "Chapter",
        toc_word: "Contents",
        homepage_word: "Course Homepage",
        homepage_url: homepage_url,
      ))
    other ->
      Error(DesugaringError(
        bl.no_blame,
        "ti2_create_menu: invalid 'language' value '"
          <> other
          <> "' (expected 'en' or 'de')",
      ))
  })

  n2t.early_return_one_to_one_nodemap_walk(root, nodemap(_, at_root_data))
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
                  language=en
                  <> Index
                    <> NextChapterOrSubTitle
                      number-chiron=1.
                      ch_no=1
                      <>
                        'Introduction'
                ",
      expected: "
                <> Document
                  language=en
                  <> Index
                    <> TopMenu
                      id=top-menu
                      <> MenuRow
                        class=menu-row
                        <> a
                          class=menu-row-placeholder
                        <> a
                          id=next-page
                          href=./1-0.html
                          class=menu-row-right
                          <>
                            'Chapter 1 >>'
                          <> span
                            style=visibility:hidden
                            id=top-next-page-tooltip
                            <>
                              'Introduction'
                    <> NextChapterOrSubTitle
                      number-chiron=1.
                      ch_no=1
                      <>
                        'Introduction'
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
