import gleam/int
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
  TextLine,
  V,
  T,
}
import nodemaps_2_desugarer_transforms as n2t
import blame as bl
import on

const prev_page_id_attribute = Attribute(bl.Des([], name, 43), "id", "prev-page")
const next_page_id_attribute = Attribute(bl.Des([], name, 44), "id", "next-page")

type Title = List(VXML)

type Page {
  Chapter(title: Title, number_chiron: String, ch_no: Int)
  Sub(title: Title, number_chiron: String, ch_no: Int, sub_no: Int)
}

type Relation {
  Prev
  Next
}

type RelatedPage {
  RelatedPage(
    page: Page,
    relation: Relation,
  )
}

type FourLinks {
  FourLinks(
    homepage: VXML,
    index: Option(VXML), // none at Index itself; takes the prev-page-id if 'prev' is None
    prev: Option(VXML),  // always chapter or sub, not the index
    next: Option(VXML),
  )
}

type Menu {
  Top
  Bottom
}

fn an_attribute(key: String, value: String) -> Attribute {
  Attribute(desugarer_blame(62), key, value)
}

fn string_2_text_node(content: String) -> VXML {
  T(desugarer_blame(66), [TextLine(desugarer_blame(66), content)])
}

fn into_list(a: a) -> List(a) {
  [a]
}

fn homepage_link(homepage_url: String) -> VXML {
  V(
    desugarer_blame(75),
    "a",
    an_attribute("href", homepage_url) |> into_list,
    string_2_text_node("zür Kursübersicht") |> into_list,
  )
}

fn index_link() -> VXML {
  V(
    desugarer_blame(84),
    "a",
    an_attribute("href", "./index.html") |> into_list,
    [
      V(
        desugarer_blame(89),
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

fn related_page_2_link(
  related_page: RelatedPage,
) -> VXML {
  let RelatedPage(page, relation) = related_page

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

  let tooltip = case relation {
    Prev -> V(
      desugarer_blame(128),
      "span",
      [
        an_attribute("style", "visibility:hidden"),
        an_attribute("id", "top-prev-page-tooltip"),
      ],
      page.title,
    )

    Next -> V(
      desugarer_blame(138),
      "span",
      [
        an_attribute("style", "visibility:hidden"),
        an_attribute("id", "top-next-page-tooltip"),
      ],
      page.title,
    )
  }

  V(
    desugarer_blame(149),
    "a",
    [
      href_attribute,
    ],
    [
      content |> string_2_text_node,
      tooltip,
    ],
  )
}

fn left_right_links_2_menu(
  left: List(VXML),
  right: List(VXML),
  which: Menu,
) -> VXML {
  let #(menu_tag, class_prefix) = case which {
    Top -> #("TopMenu", "top-")
    Bottom -> #("BottomMenu", "bottom-")
  }
  V(
    desugarer_blame(167),
    menu_tag,
    an_attribute("id", class_prefix <> "menu") |> into_list,
    [
      V(
        desugarer_blame(172),
        "MenuLeft",
        an_attribute("class", class_prefix <> "menu-left") |> into_list,
        left,
      ),
      V(
        desugarer_blame(178),
        "MenuRight",
        an_attribute("class", class_prefix <> "menu-right") |> into_list,
        right,
      ),
    ],
  )
}

fn links_2_menu(
  links: FourLinks,
  which: Menu,
) -> VXML {
  case links.index {
    // the Index
    None -> case which {
      Top -> left_right_links_2_menu(
        [links.homepage],
        [links.next] |> option.values,
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
        [links.index, links.prev] |> option.values,
        [Some(links.homepage), links.next] |> option.values,
        which,
      )
      Bottom -> left_right_links_2_menu(
        [links.prev] |> option.values,
        [links.next] |> option.values,
        which,
      )
    }
  }
}

fn get_four_links(
  homepage_link: VXML,
  index_link: Option(VXML),
  prev: Option(RelatedPage),
  next: Option(RelatedPage),
) -> FourLinks {
  FourLinks(
    homepage: homepage_link,
    index: index_link,
    prev: prev |> option.map(related_page_2_link),
    next: next |> option.map(related_page_2_link),
  )
}

fn related_page_from_title(
  vxml: VXML,
  relation: Relation,
) -> Result(Option(RelatedPage), DesugaringError) {
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
  Ok(Some(RelatedPage(page, relation)))
}

fn four_links_constructor_at_index(
  index: VXML,
  homepage_link: VXML,
) -> Result(FourLinks, DesugaringError) {
  use next <- on.ok(related_page_from_title(index, Next))
  case next {
    None -> Error(DesugaringError(bl.no_blame, "index missing PrevChapterOrSubTitle child (?)"))
    _ -> Ok(get_four_links(homepage_link, None, None, next))
  }
}

fn four_links_constructor_at_ch_or_sub(
  vxml: VXML,
  homepage_link: VXML,
  index_link: VXML,
) -> Result(FourLinks, DesugaringError) {
  use prev <- on.ok(related_page_from_title(vxml, Prev))
  use next <- on.ok(related_page_from_title(vxml, Next))
  Ok(get_four_links(homepage_link, Some(index_link), prev, next))
}

fn add_ids_to_links(
  links: FourLinks,
  which: Menu,
) -> FourLinks {
  case which {
    Top -> {
      let index = case option.is_none(links.prev) {
        False -> links.index
        True -> links.index |> option.map(infra.v_prepend_attribute(_, prev_page_id_attribute))
      }
      let prev = option.map(links.prev, infra.v_prepend_attribute(_, prev_page_id_attribute))
      let next = option.map(links.next, infra.v_prepend_attribute(_, next_page_id_attribute))
      FourLinks(links.homepage, index, prev, next)
    }
    Bottom -> {
      FourLinks(
        ..links,
        prev: links.prev |> option.map(infra.replace_attribute_value_recursive(_, "top-prev-page-tooltip", "bottom-prev-page-tooltip")),
        next: links.next |> option.map(infra.replace_attribute_value_recursive(_, "top-next-page-tooltip", "bottom-next-page-tooltip")),
      )
    }
  }
}

fn add_menu(
  node: VXML,
  links: FourLinks,
  which: Menu,
) -> VXML {
  let menu = links
    |> add_ids_to_links(which)
    |> links_2_menu(which)

  case which {
    Top -> infra.v_prepend_child(node, menu)
    Bottom -> infra.v_append_child(node, menu)
  }
}

fn nodemap(
  vxml: VXML,
  homepage_link: VXML,
  index_link: VXML,
) -> Result(#(VXML, TrafficLight), DesugaringError) {
  use #(links, continue) <- on.ok(case vxml {
    V(_, "Index", _, _) -> {
      use links <- on.ok(four_links_constructor_at_index(vxml, homepage_link))
      Ok(#(Some(links), GoBack))
    }

    V(_, "Chapter", _, _) -> {
      use links <- on.ok(four_links_constructor_at_ch_or_sub(vxml, homepage_link, index_link))
      Ok(#(Some(links), Continue))
    }

    V(_, "Sub", _, _) -> {
      use links <- on.ok(four_links_constructor_at_ch_or_sub(vxml, homepage_link, index_link))
      Ok(#(Some(links), GoBack))
    }

    V(_, "Document", _, _) -> {
      Ok(#(None, Continue))
    }

    _ -> {
      Ok(#(None, GoBack))
    }
  })

  let vxml = case links {
    None -> vxml
    Some(links) -> {
      case links.index {
        None -> vxml |> add_menu(links, Top) // the index gets no bottom menu
        Some(_) -> vxml |> add_menu(links, Top) |> add_menu(links, Bottom)
      }
    }
  }

  Ok(#(vxml, continue))
}

fn at_root(
  root: VXML
) -> Result(VXML, DesugaringError) {
  let external =
    infra.v_value_of_first_attribute_with_key(root, "external")
    |> option.unwrap("")

  n2t.early_return_one_to_one_nodemap_traverse_tree(
    root,
    nodemap(_, external |> homepage_link, index_link()),
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
