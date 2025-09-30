import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string.{inspect as ins}
import infrastructure.{
  type Desugarer,
  type DesugaringError,
  Desugarer,
} as infra
import vxml.{
  type VXML,
  type Attribute,
  Attribute,
  TextLine,
  V,
  T,
}
import nodemaps_2_desugarer_transforms as n2t
import blame as bl

type Page {
  Index
  Chapter(Int)
  Sub(Int, Int)
}

type Relation {
  Prev
  Next
  Jump
}

type FourLinks {
  FourLinks(
    homepage: VXML,
    index: Option(VXML), // is None at the index itself
    prev_chap_or_sub: Option(VXML),
    next_chap_or_sub: Option(VXML),
  )
}

const b = bl.Des([], name, 14)
const id_prev_page_attribute = Attribute(b, "id", "prev-page")
const id_next_page_attribute = Attribute(b, "id", "next-page")

fn an_attribute(key: String, value: String) -> Attribute {
  Attribute(desugarer_blame(46), key, value)
}

fn string_2_text_node(content: String) -> VXML {
  T(desugarer_blame(50), [TextLine(desugarer_blame(50), content)])
}

fn into_list(a: a) -> List(a) {
  [a]
}

fn homepage_link(homepage_url: String) -> VXML {
  V(
    b,
    "a",
    an_attribute("href", homepage_url) |> into_list,
    string_2_text_node("zür Kursübersicht") |> into_list,
  )
}

fn page_href(page: Page) -> String {
  case page {
    Index -> "./index.html"
    Chapter(ch_no) -> "./" <> ins(ch_no) <> "-0.html"
    Sub(ch_no, sub_no) -> "./" <> ins(ch_no) <> "-" <> ins(sub_no) <> ".html"
  }
}

fn related_page_2_link(
  page: Page,
  relation: Relation,
) -> VXML {
  let href_attribute = 
    page
    |> page_href
    |> an_attribute("href", _)

  let #(prev_prefix, next_suffix) = case relation {
    Prev -> #("<< ", "")
    Next -> #("", " >>")
    _ -> #("", "")
  }

  let content_t = case page {
    Index -> "Inhaltsverzeichnis"
    Chapter(ch_no) -> prev_prefix <> "Kapitel " <> ins(ch_no) <> next_suffix
    Sub(ch_no, sub_no) -> prev_prefix <> "Kapitel " <> ins(ch_no) <> "." <> ins(sub_no) <> next_suffix
  }
  |> string_2_text_node

  let span = case page, relation {
    Index, Prev -> Some(
      V(
        desugarer_blame(99),
        "span",
        an_attribute("class", "inhalts_arrows") |> into_list, 
        "<< " |> string_2_text_node |> into_list,
      )
    )
    _, _ -> None
  }

  V(
    desugarer_blame(109),
    "a",
    [
      href_attribute,
    ],
    [
      span,
      Some(content_t),
    ] |> option.values
  )
}

fn get_four_links(
  this: Page,
  prev: Option(Page),
  next: Option(Page),
  homepage_url: String,
) -> FourLinks {
  FourLinks(
    homepage: homepage_link(homepage_url),
    index: case this, prev {
      Index, _ -> None
      _, Some(Index) -> Some(related_page_2_link(Index, Prev))
      _, _ -> Some(related_page_2_link(Index, Jump))
    },
    prev_chap_or_sub: case prev {
      None -> None
      Some(Index) -> None
      Some(x) -> Some(related_page_2_link(x, Prev))
    },
    next_chap_or_sub: next |> option.map(related_page_2_link(_, Next)),
  )
}

fn add_ids_to_links(
  links: FourLinks,
) -> FourLinks {
  let index = case option.is_none(links.prev_chap_or_sub) {
    False -> links.index
    True -> links.index |> option.map(infra.v_prepend_attribute(_, id_prev_page_attribute))
  }
  let prev = option.map(links.prev_chap_or_sub, infra.v_prepend_attribute(_, id_prev_page_attribute))
  let next = option.map(links.next_chap_or_sub, infra.v_prepend_attribute(_, id_next_page_attribute))
  FourLinks(
    links.homepage,
    index,
    prev,
    next,
  )
}

fn links_2_left_menu(
  links: FourLinks,
) -> VXML {
  case links.index {
    None ->
      // this is the index:
      V(
        desugarer_blame(167),
        "LeftMenu",
        an_attribute("class", "menu-left") |> into_list,
        [links.homepage],
      )
    _ ->
      // this is not the index:
      V(
        desugarer_blame(175),
        "LeftMenu",
        an_attribute("class", "menu-left") |> into_list,
        option.values([links.index, links.prev_chap_or_sub]),
      )
  }
}

fn links_2_right_menu(
  links: FourLinks
) -> VXML {
  case links.index {
    None ->
      // this is the index:
      V(
        desugarer_blame(190),
        "RightMenu",
        an_attribute("class", "menu-right") |> into_list,
        option.values([links.next_chap_or_sub]),
      )
    _ ->
      // this is not the index:
      V(
        desugarer_blame(198),
        "RightMenu",
        an_attribute("class", "menu-right") |> into_list,
        option.values([Some(links.homepage), links.next_chap_or_sub]),
      )
  }
}

fn links_2_menu(
  links: FourLinks
) -> VXML {
  V(
    desugarer_blame(210),
    "Menu",
    an_attribute("id", "menu") |> into_list,
    [
      links_2_left_menu(links),
      links_2_right_menu(links),
    ]
  )
}

fn add_menu_to_thing(
  node: VXML,
  this: Page,
  prev: Option(Page),
  next: Option(Page),
  homepage_url: String,
) -> VXML {
  let links = get_four_links(this, prev, next, homepage_url)
  let links_w_ids = links |> add_ids_to_links
  let menu = links_2_menu(links_w_ids)
  infra.v_prepend_child(node, menu)
}

fn add_menus_in_subchapters(
  ch: VXML,
  ch_no: Int,
  pages_idx: Int,
  pages: List(Page),
  homepage_url: String,
) -> #(Int, VXML) {
  let assert V(_, _, _, children) = ch
  let #(acc, children) = list.map_fold(
    children,
    pages_idx,
    fn(acc, child) {
      case child {
        V(_, "Sub", _, _) -> {
          let assert Ok(Sub(x, y) as this) = infra.get_at(pages, acc)
          let sub_no = acc + 1 - pages_idx
          assert x == ch_no
          assert y == sub_no
          let child = add_menu_to_thing(
            child,
            this,
            infra.get_at(pages, acc - 1) |> option.from_result,
            infra.get_at(pages, acc + 1) |> option.from_result,
            homepage_url,
          )
          #(acc + 1, child)
        }
        _ -> #(acc, child)
      }
    }
  )
  #(acc, V(..ch, children: children))
}

fn get_course_homepage(document: VXML) -> String {
  case infra.v_first_attribute_with_key(document, "course_homepage") {
    None -> ""
    Some(x) -> x.value
  }
}

fn gather_pages_chapter_level(ch: VXML, ch_no: Int, previous: List(Page)) -> List(Page) {
  let assert V(_, _, _, children) = ch
  let acc = list.fold(
    children,
    #(1, previous),
    fn (acc, thing) {
      let #(sub_no, pages) = acc
      case thing {
        V(_, "Sub", _, _) -> #(sub_no + 1, [Sub(ch_no, sub_no), ..pages])
        _ -> acc
      }
    }
  )
  acc.1
}

fn gather_pages_root_level(root: VXML) -> List(Page) {
  let assert V(_, _, _, children) = root
  let acc = list.fold(
    children,
    #(1, []),
    fn (acc, thing) {
      let #(ch_no, pages) = acc
      case thing {
        V(_, "Index", _, _) -> #(ch_no, [Index, ..pages])
        V(_, "Chapter", _, _) -> {
          let pages = gather_pages_chapter_level(thing, ch_no, [Chapter(ch_no), ..pages])
          #(ch_no + 1, pages)
        }
        _ -> acc
      }
    }
  )
  acc.1 |> list.reverse
}

fn at_root(root: VXML) -> Result(VXML, DesugaringError) {
  let assert V(_, "Document", _, children) = root
  let homepage_url = get_course_homepage(root)
  let pages = gather_pages_root_level(root)
  let #(_, children) = list.map_fold(
    children,
    0,
    fn (acc, thing) {
      case thing {
        V(_, "Index", _, _) -> {
          assert acc == 0
          let assert Ok(Index as this) = infra.get_at(pages, acc)
          let thing = add_menu_to_thing(
            thing,
            this,
            infra.get_at(pages, acc - 1) |> option.from_result,
            infra.get_at(pages, acc + 1) |> option.from_result,
            homepage_url,
          )
          #(acc + 1, thing)
        }
        V(_, "Chapter", _, _) -> {
          let assert Ok(Chapter(ch_no) as this) = infra.get_at(pages, acc)
          let thing = add_menu_to_thing(
            thing,
            this,
            infra.get_at(pages, acc - 1) |> option.from_result,
            infra.get_at(pages, acc + 1) |> option.from_result,
            homepage_url,
          )
          let #(acc, thing) = add_menus_in_subchapters(
            thing,
            ch_no,
            acc + 1,
            pages,
            homepage_url,
          )
          // for clarity:
          #(acc, thing)
        }
        _ -> #(acc, thing)
      }
    }
  )
  Ok(V(..root, children: children))
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

pub const name = "ti2_add_prev_next_chapters_attributes"
fn desugarer_blame(line_no: Int) { bl.Des([], name, line_no) }

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// generates prev-ch-or-sub-title, prev-ch-or-sub-number, 
/// next-ch-or-sub-title, next-ch-or-sub-number attributes
/// for all chapters/subchapters that respectively
/// have a previous or next Chapter or Sub element
/// in the document flow;
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
