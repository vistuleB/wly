import gleam/list
import gleam/option.{type Option, Some}
import gleam/result
import gleam/string.{inspect as ins}
import infrastructure.{type Desugarer, Desugarer, type DesugarerTransform, type DesugaringError, type DesugaringWarning, DesugaringError} as infra
import vxml.{type VXML, Attribute, V}
import blame as bl
import nodemaps_2_desugarer_transforms as n2t
import on

fn chapter_link(
  chapter_link_component_name: String,
  item: VXML,
  count: Int,
) -> Result(VXML, DesugaringError) {
  let assert V(blame, tag, _, _) = item
  let tp = case tag {
    _ if tag == "Chapter" -> "chapter"
    _ if tag == "Bootcamp" -> "bootcamp"
    _ -> panic as "expecting 'Chapter' or 'Bootcamp'"
  }

  use title_element <- on.error_ok(
    infra.v_unique_child_with_tag(item, "ArticleTitle"),
    fn (s) {
      case s {
        infra.MoreThanOne -> Error(DesugaringError(item.blame, "has more than one ArticleTitle child"))
        infra.LessThanOne -> Error(DesugaringError(item.blame, "has no ArticleTitle child"))
      }
    }
  )

  let assert V(_, _, _, _) = title_element

  Ok(
    V(
      blame,
      chapter_link_component_name,
      [
        Attribute(desugarer_blame(40), "article_type", ins(count)),
        Attribute(desugarer_blame(41), "href", tp <> ins(count)),
      ],
      title_element.children,
    ),
  )
}

fn type_of_chapters_title(
  type_of_chapters_title_component_name: String,
  label: String,
) -> VXML {
  V(
    desugarer_blame(53),
    type_of_chapters_title_component_name,
    [Attribute(desugarer_blame(55), "label", label)],
    [],
  )
}

fn div_with_id_title_and_menu_items(
  type_of_chapters_title_component_name: String,
  id: String,
  title_label: String,
  menu_items: List(VXML),
) -> VXML {
  V(
    desugarer_blame(67),
    "div",
    [
      Attribute(desugarer_blame(70), "id", id)
    ],
    [
      type_of_chapters_title(type_of_chapters_title_component_name, title_label),
      V(desugarer_blame(74), "ul", [], menu_items),
    ],
  )
}

fn at_root(root: VXML, param: InnerParam) -> Result(#(VXML, List(DesugaringWarning)), DesugaringError) {
  let #(
    table_of_contents_tag,
    type_of_chapters_title_component_name,
    chapter_link_component_name,
    maybe_spacer,
  ) = param

  use chapter_menu_items <- result.try(
    infra.v_children_with_tag(root, "Chapter")
    |> list.index_map(fn(chapter: VXML, index) { chapter_link(chapter_link_component_name, chapter, index + 1) })
    |> result.all
  )

  use bootcamp_menu_items <- result.try(
    infra.v_children_with_tag(root, "Bootcamp")
    |> list.index_map(fn(bootcamp: VXML, index) { chapter_link(chapter_link_component_name, bootcamp, index + 1) })
    |> result.all
  )

  let chapters_div =
    div_with_id_title_and_menu_items(
      type_of_chapters_title_component_name,
      "chapter",
      "Chapters",
      chapter_menu_items,
    )

  let bootcamps_div =
    div_with_id_title_and_menu_items(
      type_of_chapters_title_component_name,
      "bootcamp",
      "Bootcamps",
      bootcamp_menu_items,
    )

  let exists_bootcamps = !list.is_empty(bootcamp_menu_items)
  let exists_chapters = !list.is_empty(chapter_menu_items)

  let children = list.flatten([
    case exists_chapters {
      True -> [chapters_div]
      False -> []
    },
    case exists_bootcamps, exists_chapters, maybe_spacer {
      True, True, Some(spacer_tag) -> [V(desugarer_blame(124), spacer_tag, [], [])]
      _, _, _ -> []
    },
    case exists_bootcamps {
      True -> [bootcamps_div]
      False -> []
    },
  ])

  infra.v_prepend_child(root, V(desugarer_blame(133), table_of_contents_tag, [], children))
  |> n2t.add_no_warnings
  |> Ok
}

fn desugarer_factory(param: InnerParam) -> infra.DesugarerTransform {
  at_root(_, param)
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(param)
}

type Param = #(String,   String,                String,        Option(String))
//             ↖         ↖                      ↖              ↖
//             tag name  tag name               tag name       optional tag name
//             table of  of 'big title'         individual     for spacer between
//             contents  (Chapters, Bootcamps)  chapter links  two groups of chapter links
type InnerParam = Param

pub const name = "generate_lbp_table_of_contents"
fn desugarer_blame(line_no: Int) {bl.Des([], name, line_no)}

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// generates the LBP table of contents while
/// admitting custom values for the root tag name
/// of the table of contents, as well as for the tag
/// name of the chapter (& bootcamp) links and the
/// tag name for the Chapter/Bootcamp category
/// banners, and an optional spacer tag name for an
/// element to be placed between the two categories
pub fn constructor(param: Param) -> Desugarer {
  Desugarer(
    name: name,
    stringified_param: option.None,
    stringified_outside: option.None,
    transform: case param_to_inner_param(param) {
      Error(error) -> fn(_) { Error(error) }
      Ok(param) -> desugarer_factory(param)
    }
  )
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
fn assertive_tests_data() -> List(infra.AssertiveTestData(Param)) {
  []
}

pub fn assertive_tests() {
  infra.assertive_test_collection_from_data(name, assertive_tests_data(), constructor)
}
