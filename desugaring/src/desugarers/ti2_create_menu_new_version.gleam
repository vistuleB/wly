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

type FourLinks {
  FourLinks(
    homepage: VXML,
    index: Option(VXML), // none at Index itself; takes the prev-page-id if 'prev' is None
    prev: Option(VXML),  // always chapter or sub, not the index
    next: Option(VXML),
  )
}

fn an_attribute(key: String, value: String) -> Attribute {
  Attribute(desugarer_blame(50), key, value)
}

fn string_2_text_node(content: String) -> VXML {
  T(desugarer_blame(54), [TextLine(desugarer_blame(54), content)])
}

fn into_list(a: a) -> List(a) {
  [a]
}

fn homepage_link(homepage_url: String) -> VXML {
  V(
    desugarer_blame(63),
    "a",
    an_attribute("href", homepage_url) |> into_list,
    string_2_text_node("zür Kursübersicht") |> into_list,
  )
}

fn index_link() -> VXML {
  V(
    desugarer_blame(72),
    "a",
    an_attribute("href", "./index.html") |> into_list,
    [
      V(
        desugarer_blame(77),
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

fn prev_next_page_to_link(
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
  }

  let content = case page {
    Chapter(_, _, ch_no) -> prev_prefix <> "Kapitel " <> ins(ch_no) <> next_suffix
    Sub(_, _, ch_no, sub_no) -> prev_prefix <> "Kapitel " <> ins(ch_no) <> "." <> ins(sub_no) <> next_suffix
  }

  let tooltip = case relation {
    Prev -> V(
      desugarer_blame(115),
      "span",
      [
        an_attribute("style", "visibility:hidden"),
        an_attribute("id", "prev-page-tooltip"),
      ],
      page.title,
    )

    Next -> V(
      desugarer_blame(125),
      "span",
      [
        an_attribute("style", "visibility:hidden"),
        an_attribute("id", "next-page-tooltip"),
      ],
      page.title,
    )
  }

  V(
    desugarer_blame(136),
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

fn add_ids_to_links(
  links: FourLinks,
) -> FourLinks {
  let index = case option.is_none(links.prev) {
    False -> links.index
    True -> links.index |> option.map(infra.v_prepend_attribute(_, prev_page_id_attribute))
  }
  let prev = option.map(links.prev, infra.v_prepend_attribute(_, prev_page_id_attribute))
  let next = option.map(links.next, infra.v_prepend_attribute(_, next_page_id_attribute))
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
  let prev_div = case links.prev {
    None -> None
    Some(x) -> Some(V(
      desugarer_blame(171),
      "div",
      [],
      [x],
    ))
  }

  case links.index {
    None ->
      // we are the index:
      V(
        desugarer_blame(182),
        "LeftMenu",
        an_attribute("class", "menu-left") |> into_list,
        [links.homepage],
      )
    _ ->
      // we are not the index:
      V(
        desugarer_blame(190),
        "LeftMenu",
        an_attribute("class", "menu-left") |> into_list,
        option.values([links.index, prev_div]),
      )
  }
}

fn links_2_right_menu(
  links: FourLinks
) -> VXML {
  let next_div = case links.next {
    None -> None
    Some(x) -> Some(V(
      desugarer_blame(204),
      "div",
      [],
      [x],
    ))
  }

  case links.index {
    None -> {
      // this is the index:
      V(
        desugarer_blame(215),
        "RightMenu",
        an_attribute("class", "menu-right") |> into_list,
        option.values([next_div]),
      )
    }
    _ -> {
      // this is not the index:
      V(
        desugarer_blame(224),
        "RightMenu",
        an_attribute("class", "menu-right") |> into_list,
        option.values([
          Some(links.homepage), 
          next_div,
        ]),
      )
    }
  }
}

fn links_2_menu(
  links: FourLinks
) -> VXML {
  V(
    desugarer_blame(240),
    "Menu",
    an_attribute("id", "menu") |> into_list,
    [
      links_2_left_menu(links),
      links_2_right_menu(links),
    ]
  )
}

fn get_four_links(
  homepage_link: VXML,
  index_link: Option(VXML),
  prev: Option(Page),
  next: Option(Page),
) -> FourLinks {
  FourLinks(
    homepage: homepage_link,
    index: index_link,
    prev: prev |> option.map(prev_next_page_to_link(_, Prev)),
    next: next |> option.map(prev_next_page_to_link(_, Next)),
  )
}

fn page_associated_to_title_tag(
  vxml: VXML,
  title_tag: String,
) -> Result(Option(Page), DesugaringError) {
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
  case sub_no {
    None -> Ok(Some(Chapter(title, chiron, ch_no)))
    Some(sub_no) -> Ok(Some(Sub(title, chiron, ch_no, sub_no)))
  }
}

fn next_page(vxml: VXML) -> Result(Option(Page), DesugaringError) {
  page_associated_to_title_tag(vxml, "NextChapterOrSubTitle")
}

fn prev_page(vxml: VXML) -> Result(Option(Page), DesugaringError) {
  page_associated_to_title_tag(vxml, "PrevChapterOrSubTitle")
}

fn four_links_constructor_at_index(
  index: VXML,
  homepage_link: VXML,
) -> Result(FourLinks, DesugaringError) {
  use next <- on.ok(next_page(index))
  case next {
    None -> Error(DesugaringError(bl.no_blame, "index missing PrevChapterOrSubTitle child (?)"))
    Some(x) -> Ok(get_four_links(homepage_link, None, None, Some(x)))
  }
}

fn four_links_constructor_at_ch_or_sub(
  vxml: VXML,
  homepage_link: VXML,
  index_link: VXML,
) -> Result(FourLinks, DesugaringError) {
  use prev <- on.ok(prev_page(vxml))
  use next <- on.ok(next_page(vxml))
  Ok(get_four_links(homepage_link, Some(index_link), prev, next))
}

fn add_menu_from_from_four_links(
  node: VXML,
  links: FourLinks,
) -> VXML {
  links
  |> add_ids_to_links
  |> links_2_menu
  |> infra.v_prepend_child(node, _)
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
    Some(links) -> add_menu_from_from_four_links(vxml, links)
  }
  Ok(#(vxml, continue))
}

fn at_root(
  root: VXML
) -> Result(VXML, DesugaringError) {
  let external =
    infra.v_value_of_first_attribute_with_key(root, "external")
    |> option.unwrap("")

  n2t.early_return_one_to_one_nodemap_recursive_application(
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

pub const name = "ti2_create_menu_new_version"
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
