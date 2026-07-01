import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string.{inspect as ins}
import infrastructure.{
  type Desugarer,
  type DesugaringError,
  type TrafficLight,
  DesugaringError,
  Desugarer,
  GoBack,
  Continue,
} as infra
import vxml.{
  type VXML,
  type Attr,
  Attr,
  Line,
  V,
  T,
}
import nodemaps_2_desugarer_transforms as n2t
import blame as bl
import on

const prev_page_id_attr = Attr(bl.Des([], name, 26), "id", "prev-page")
const next_page_id_attr = Attr(bl.Des([], name, 27), "id", "next-page")
const hr_id_attr = Attr(bl.Des([], name, 27), "id", "bottom-menu-hr")
const hr = V(bl.Des([], name, 15), "hr", [hr_id_attr], [])

type Title = List(VXML)

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

fn an_attr(key: String, val: String) -> Attr {
  Attr(desugarer_blame(67), key, val)
}

fn string_2_text_node(content: String) -> VXML {
  T(desugarer_blame(71), [Line(desugarer_blame(71), content)])
}

fn into_list(a: a) -> List(a) {
  [a]
}

fn homepage_link(at_root_data: ConstructedAtRootData) -> Option(VXML) {
  case at_root_data.homepage_url {
    "" -> None
    url ->
      Some(V(
        desugarer_blame(83),
        "a",
        an_attr("href", url) |> into_list,
        string_2_text_node(at_root_data.homepage_word) |> into_list,
      ))
  }
}

fn index_link(toc_word: String) -> VXML {
  V(
    desugarer_blame(93),
    "a",
    an_attr("href", "./index.html") |> into_list,
    [
      V(
        desugarer_blame(98),
        "span",
        an_attr("class", "inhalts_arrows") |> into_list,
        "<< " |> string_2_text_node |> into_list,
      ),
      toc_word |> string_2_text_node,
    ],
  )
}

fn page_href(page: Page) -> String {
  case page {
    Chapter(_, _, ch_no) -> "./" <> ins(ch_no) <> "-0.html"
    Sub(_, _, ch_no, sub_no) ->
      "./" <> ins(ch_no) <> "-" <> ins(sub_no) <> ".html"
  }
}

fn tooltip(
  page: Page,
  relation: Relation,
  which: Menu,
) -> VXML {
  let p1 = case which {
    Top -> "top-"
    Bottom -> "bottom-"
  }

  let p2 = case relation {
    Prev -> "prev-"
    Next -> "next-"
  }

  V(
    desugarer_blame(132),
    "span",
    [
      an_attr("style", "visibility:hidden"),
      an_attr("id", p1 <> p2 <> "page-tooltip"),
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
    |> an_attr("href", _)

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

  V(
    desugarer_blame(172),
    "a",
    [href_attr],
    [
      content |> string_2_text_node,
      tooltip(page, relation, which),
    ],
  )
}

fn row1_row2_links_2_menu(
  row1: #(Option(VXML), Option(VXML)),
  row2: #(Option(VXML), Option(VXML)),
  which: Menu,
) -> VXML {
  let #(tag, p1) = case which {
    Top -> #("TopMenu", "top-")
    Bottom -> #("BottomMenu", "bottom-")
  }
  let dummy =
    V(desugarer_blame(192), "a", [an_attr("class", "menu-row-placeholder")], [])
  let row_constructor = fn(row: #(Option(VXML), Option(VXML))) {
    let #(left, right) = row
    let right = case right {
      None -> None
      Some(x) -> Some(infra.v_append_classes(x, "menu-row-right"))
    }
    case left, right {
      None, None -> None
      _, _ -> {
        let left = option.unwrap(left, dummy)
        let right = option.unwrap(right, dummy)
        Some(V(
          desugarer_blame(205),
          "MenuRow",
          an_attr("class", "menu-row") |> into_list,
          [left, right],
        ))
      }
    }
  }
  V(
    desugarer_blame(214),
    tag,
    an_attr("id", p1 <> "menu") |> into_list,
    [row1, row2] |> list.map(row_constructor) |> option.values,
  )
}

fn data_2_menu_row_version(
  data: LinkData,
  which: Menu,
) -> VXML {
  let chapter_word = data.at_root_data.chapter_word
  let toc_word = data.at_root_data.toc_word
  let homepage = homepage_link(data.at_root_data)

  case data.index {
    // the Index
    None ->
      case which {
        Top ->
          row1_row2_links_2_menu(
            #(
              homepage,
              data.next
                |> option.map(page_link(_, Next, which, chapter_word))
                |> option.map(infra.v_prepend_attr(_, next_page_id_attr)),
            ),
            #(None, None),
            which,
          )

        Bottom ->
          row1_row2_links_2_menu(
            #(None, None),
            #(None, None),
            which,
          )
      }

    // a chapter or subchapter
    _ ->
      case which {
        Top ->
          row1_row2_links_2_menu(
            #(
              case data.prev {
                None ->
                  index_link(toc_word) |> infra.v_prepend_attr(prev_page_id_attr)
                _ -> index_link(toc_word)
              }
                |> Some,
              homepage,
            ),
            #(
              data.prev
                |> option.map(page_link(_, Prev, which, chapter_word))
                |> option.map(infra.v_prepend_attr(_, prev_page_id_attr)),
              data.next
                |> option.map(page_link(_, Next, which, chapter_word))
                |> option.map(infra.v_prepend_attr(_, next_page_id_attr)),
            ),
            which,
          )

        Bottom ->
          row1_row2_links_2_menu(
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

fn page_from_title(
  vxml: VXML,
  relation: Relation,
) -> Result(Option(Page), DesugaringError) {
  let title_tag = case relation {
    Prev -> "PrevChapterOrSubTitle"
    Next -> "NextChapterOrSubTitle"
  }
  use title <- on.eager_none_some(
    infra.v_first_child_with_tag(vxml, title_tag),
    Ok(None),
  )
  let assert V(blame, _, attrs, title) = title
  use chiron <- on.ok(infra.attrs_val_of_unique_key(attrs, "number-chiron", blame))
  use ch_no <- on.ok(infra.attrs_val_of_unique_key(attrs, "ch_no", blame))
  let assert Ok(ch_no) = int.parse(ch_no)
  let sub_no = case infra.attrs_val_of_unique_key(attrs, "sub_no", blame) {
    Ok(x) -> {
      let assert Ok(x) = int.parse(x)
      Some(x)
    }
    _ -> None
  }
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
        "index missing NextChapterOrSubTitle child (?)",
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

fn add_menu(
  node: VXML,
  data: LinkData,
  which: Menu,
) -> VXML {
  let menu = data_2_menu_row_version(data, which)
  case which {
    Top -> infra.v_prepend_child(node, menu)
    Bottom ->
      infra.v_pour_before_first(
        node,
        [menu, hr],
        "Sub",
      )
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
    infra.v_val_of_first_attr_with_key(root, "homepage")
    |> option.unwrap("")

  use language <- on.ok(case infra.v_val_of_first_attr_with_key(root, "language") {
    None ->
      Error(DesugaringError(
        bl.no_blame,
        "ti2_create_menu: missing 'language' attribute on document root",
      ))
    Some(lang) -> Ok(lang)
  })

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

fn transform_factory(_: InnerParam) -> infra.DesugarerTransform {
  at_root
  |> n2t.at_root_2_desugarer_transform
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(param)
}

type Param = Nil
type InnerParam = Nil

pub const name = "ti2_create_menu"

fn desugarer_blame(line_no: Int) {
  bl.Des([], name, line_no)
}

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// generate ti2 Menu navigation with left and right
/// menus containing previous/next chapter links,
/// index link, and course homepage link. The menu
/// is inserted after each Chapter and Sub element.
/// This desugarer expects ti2_create_index and
/// ti2_add_prev_next_chapter_title_elements to have
/// been run beforehand
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
  infra.assertive_test_collection_from_data_no_param(
    name,
    assertive_tests_data(),
    constructor,
  )
}
