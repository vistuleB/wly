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
  type Attribute,
  Attribute,
  Line,
  V,
  T,
}
import nodemaps_2_desugarer_transforms as n2t
import blame as bl
import on

const prev_page_id_attr = Attribute(bl.Des([], name, 26), "id", "prev-page")
const next_page_id_attr = Attribute(bl.Des([], name, 27), "id", "next-page")
const hr_id_attr = Attribute(bl.Des([], name, 27), "id", "bottom-menu-hr")
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

type LinkData {
  LinkData(
    homepage_url: String,
    index: Option(String),
    prev: Option(Page),
    next: Option(Page),
  )
}

type Menu {
  Top
  Bottom
}

fn an_attribute(key: String, value: String) -> Attribute {
  Attribute(desugarer_blame(58), key, value)
}

fn string_2_text_node(content: String) -> VXML {
  T(desugarer_blame(62), [Line(desugarer_blame(62), content)])
}

fn into_list(a: a) -> List(a) {
  [a]
}

fn homepage_link(homepage_url: String) -> VXML {
  V(
    desugarer_blame(71),
    "a",
    an_attribute("href", homepage_url) |> into_list,
    string_2_text_node("zür Kursübersicht") |> into_list,
  )
}

fn index_link() -> VXML {
  V(
    desugarer_blame(80),
    "a",
    an_attribute("href", "./index.html") |> into_list,
    [
      V(
        desugarer_blame(85),
        "span",
        an_attribute("class", "inhalts_arrows") |> into_list, 
        "<< " |> string_2_text_node |> into_list,
      ),
      "Inhaltsverzeichnis" |> string_2_text_node
    ]
  )
}

fn page_href(page: Page) -> String {
  case page {
    Chapter(_, _, ch_no) -> "./" <> ins(ch_no) <> "-0.html"
    Sub(_, _, ch_no, sub_no) -> "./" <> ins(ch_no) <> "-" <> ins(sub_no) <> ".html"
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
    desugarer_blame(118),
    "span",
    [
      an_attribute("style", "visibility:hidden"),
      an_attribute("id", p1 <> p2 <> "page-tooltip"),
    ],
    page.title,
  )
}

fn page_link(
  page: Page,
  relation: Relation,
  which: Menu,
) -> VXML {
  let href_attribute = 
    page
    |> page_href
    |> an_attribute("href", _)

  let #(prev_prefix, next_suffix) = case relation {
    Prev -> #("<< ", "")
    Next -> #("", " >>")
  }

  let content = case page {
    Chapter(_, _, ch_no) -> prev_prefix <> "Kapitel " <> ins(ch_no) <> next_suffix
    Sub(_, _, ch_no, sub_no) -> prev_prefix <> "Kapitel " <> ins(ch_no) <> "." <> ins(sub_no) <> next_suffix
  }

  V(
    desugarer_blame(149),
    "a",
    [
      href_attribute,
    ],
    [
      content |> string_2_text_node,
      tooltip(page, relation, which),
    ],
  )
}

fn left_right_links_2_menu(
  left: List(VXML),
  right: List(VXML),
  which: Menu,
) -> VXML {
  let #(tag, p1) = case which {
    Top -> #("TopMenu", "top-")
    Bottom -> #("BottomMenu", "bottom-")
  }
  V(
    desugarer_blame(171),
    tag,
    an_attribute("id", p1 <> "menu") |> into_list,
    [
      V(
        desugarer_blame(176),
        "MenuLeft",
        an_attribute("id", p1 <> "menu-left") |> into_list,
        left,
      ),
      V(
        desugarer_blame(182),
        "MenuRight",
        an_attribute("id", p1 <> "menu-right") |> into_list,
        right,
      ),
    ],
  )
}

fn data_2_menu(
  data: LinkData,
  which: Menu,
) -> VXML {
  case data.index {
    // the Index
    None -> case which {
      Top -> left_right_links_2_menu(
        [
          data.homepage_url |> homepage_link(),
        ],
        [
          data.next |> option.map(page_link(_, Next, which)),
        ] |> option.values |> infra.map_first(infra.v_prepend_attribute(_, next_page_id_attr)),
        which,
      )

      Bottom -> left_right_links_2_menu(
        [],
        [],
        which,
      )
    }

    // a chapter or subchapter
    _ -> case which {
      Top -> left_right_links_2_menu(
        [
          data.prev |> option.map(page_link(_, Prev, which)),
          Some(index_link()),
        ] |> option.values |> infra.map_first(infra.v_prepend_attribute(_, prev_page_id_attr)) |> list.reverse,
        [
          Some(data.homepage_url |> homepage_link()),
          data.next |> option.map(page_link(_, Next, which)) |> option.map(infra.v_prepend_attribute(_, next_page_id_attr)),
        ] |> option.values,
        which,
      )

      Bottom -> left_right_links_2_menu(
        [
          data.prev |> option.map(page_link(_, Prev, which))
        ] |> option.values,
        [
          data.next |> option.map(page_link(_, Next, which))
        ] |> option.values,
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
  use title <- on.none_some(
    infra.v_first_child_with_tag(vxml, title_tag),
    Ok(None),
  )
  let assert V(blame, _, attrs, title) = title
  use chiron <- on.ok(infra.attributes_value_of_unique_key(attrs, "number-chiron", blame))
  use ch_no <- on.ok(infra.attributes_value_of_unique_key(attrs, "ch_no", blame))
  let assert Ok(ch_no) = int.parse(ch_no)
  let sub_no = case infra.attributes_value_of_unique_key(attrs, "sub_no", blame) {
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
  homepage_url: String,
) -> Result(LinkData, DesugaringError) {
  use next <- on.ok(page_from_title(index, Next))
  case next {
    None -> Error(DesugaringError(bl.no_blame, "index missing NextChapterOrSubTitle child (?)"))
    _ -> Ok(LinkData(homepage_url, None, None, next))
  }
}

fn link_data_at_ch_or_sub(
  vxml: VXML,
  homepage_url: String,
) -> Result(LinkData, DesugaringError) {
  use prev <- on.ok(page_from_title(vxml, Prev))
  use next <- on.ok(page_from_title(vxml, Next))
  Ok(LinkData(homepage_url, Some("./index.html"), prev, next))
}

fn add_menu(
  node: VXML,
  data: LinkData,
  which: Menu,
) -> VXML {
  let menu = data_2_menu(data, which)
  case which {
    Top -> infra.v_prepend_child(node, menu)
    Bottom -> infra.v_pour_before_first(
      node,
      [
        menu,
        hr,
      ],
      "Sub",
    )
  }
}

fn nodemap(
  vxml: VXML,
  homepage_url: String,
) -> Result(#(VXML, TrafficLight), DesugaringError) {
  use #(data, continue) <- on.ok(case vxml {
    V(_, "Index", _, _) -> {
      use data <- on.ok(link_data_at_index(vxml, homepage_url))
      Ok(#(Some(data), GoBack))
    }

    V(_, "Chapter", _, _) -> {
      use data <- on.ok(link_data_at_ch_or_sub(vxml, homepage_url))
      Ok(#(Some(data), Continue))
    }

    V(_, "Sub", _, _) -> {
      use data <- on.ok(link_data_at_ch_or_sub(vxml, homepage_url))
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
        None -> vxml |> add_menu(data, Top) // the index gets no bottom menu
        Some(_) -> vxml |> add_menu(data, Top) |> add_menu(data, Bottom)
      }
    }
  }

  Ok(#(vxml, continue))
}

fn at_root(
  root: VXML
) -> Result(VXML, DesugaringError) {
  let homepage_url =
    infra.v_value_of_first_attribute_with_key(root, "external")
    |> option.unwrap("")

  n2t.early_return_one_to_one_nodemap_traverse_tree(
    root,
    nodemap(_, homepage_url),
  )
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
fn desugarer_blame(line_no: Int) { bl.Des([], name, line_no) }

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
  infra.assertive_test_collection_from_data_no_param(name, assertive_tests_data(), constructor)
}
