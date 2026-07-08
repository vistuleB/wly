import blame as bl
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string.{inspect as ins}
import infrastructure.{
  type Desugarer,
  type DesugarerTransform,
  type DesugaringError,
  DesugaringError,
  Desugarer,
} as infra
import nodemaps_2_desugarer_transforms as n2t
import on
import vxml.{type VXML, type Line, Attr, Line, T, V}

fn reversed_lines_super_trim_end_and_remove_ending_period(lines: List(Line)) -> List(Line) {
  case lines {
    [] -> []
    [last, ..rest] -> {
      let content = string.trim_end(last.content)
      case content {
        "" -> reversed_lines_super_trim_end_and_remove_ending_period(rest)
        _ -> case string.ends_with(content, ".") && !string.ends_with(content, "..") {
          True -> {
            let last = Line(..last, content: {content |> string.drop_end(1)})
            [last, ..rest] |> reversed_lines_super_trim_end_and_remove_ending_period
          }
          False -> lines
        }
      }
    }
  }
}

fn t_super_trim_end_and_remove_ending_period(node: VXML) -> Option(VXML) {
  let assert T(blame, lines) = node
  let lines = reversed_lines_super_trim_end_and_remove_ending_period(lines |> list.reverse)
  case lines {
    [] -> None
    _ -> Some(T(blame, lines |> list.reverse))
  }
}

fn remove_period(nodes: List(VXML)) -> List(VXML) {
  use last, head <- on.eager_empty_nonempty(nodes |> list.reverse, [])

  case last {
    T(..) -> case t_super_trim_end_and_remove_ending_period(last) {
      None -> head |> list.reverse
      Some(last) -> [last, ..head] |> list.reverse
    }
    V(_, _, _, children) -> {
      let last = V(..last, children: remove_period(children))
      [last, ..head] |> list.reverse
    }
  }
}

fn lowercase_t(t: VXML) -> VXML {
  let assert T(b, contents) = t
  contents
  |> list.map(fn(line) { Line(..line, content: string.lowercase(line.content)) })
  |> T(b, _)
}

fn lowercase_vxml(node: VXML) -> VXML {
  case node {
    T(_, _) -> lowercase_t(node)
    V(_, _, _, children) ->
      V(..node, children: list.map(children, lowercase_vxml))
  }
}

fn cleanup_children(children: List(VXML)) -> List(VXML) {
  children
  |> list.map(lowercase_vxml)
  |> remove_period
}

fn construct_breadcrumb(
  children: List(VXML),
  target_id: String,
  index: Int,
) -> VXML {
  V(
    desugarer_blame(87),
    "BreadcrumbItem",
    [Attr(desugarer_blame(89), "id", "breadcrumb-" <> ins(index))],
    [
      V(
        desugarer_blame(92),
        "ThisPageLink",
        [Attr(desugarer_blame(94), "href", "?id=" <> target_id)],
        children |> cleanup_children,
      ),
    ],
  )
}

fn map_section(section: VXML, index: Int) -> Result(VXML, DesugaringError) {
  case infra.v_get_children(section) {
    [V(_, "BreadcrumbTitle", _, children), ..] -> {
      let section_id = infra.v_val_of_first_attr_with_key(section, "id")
      let target_id = option.unwrap(section_id, "section-" <> ins(index + 1))
      Ok(construct_breadcrumb(children, target_id, index))
    }
    _ ->
      Error(DesugaringError(
        section.blame,
        "Section must have a BreadcrumbTitle as first child",
      ))
  }
}

fn generate_sections_list(
  sections: List(VXML),
  exercises: List(VXML),
) -> Result(VXML, DesugaringError) {
  use sections_nodes <- on.ok(
    list.index_map(sections, map_section)
    |> result.all,
  )

  let exercises_node = case exercises {
    [] -> []
    [one] -> {
      [
        construct_breadcrumb(
          [T(one.blame, [Line(one.blame, "exercises")])],
          "exercises",
          list.length(sections_nodes),
        ),
      ]
    }
    _ -> panic as "there should not be more than one exercises section"
  }

  Ok(V(
    desugarer_blame(140),
    "SectionsBreadcrumbs",
    [],
    list.flatten([sections_nodes, exercises_node]),
  ))
}

fn remove_breadcrumb_title(vxml: VXML) -> VXML {
  case vxml {
    V(_, "Section", _, children) -> {
      let assert [V(_, "BreadcrumbTitle", _, _), ..] = children
      V(..vxml, children: list.drop(children, 1))
    }
    _ -> vxml
  }
}

fn map_chapter(child: VXML) -> Result(VXML, DesugaringError) {
  case child {
    V(b, tag, a, children)
      if tag == "Chapter" || tag == "Bootcamp" || tag == "Appendix"
    -> {
      let sections = infra.v_children_with_tag(child, "Section")
      let exercises = infra.v_children_with_tag(child, "Exercises")
      use sections_ul <- on.ok(generate_sections_list(sections, exercises))
      Ok(
        V(b, tag, a, [
          sections_ul,
          ..children
          |> list.map(remove_breadcrumb_title)
        ]),
      )
    }
    _ -> Ok(child)
  }
}

fn at_root(root: VXML) -> Result(VXML, DesugaringError) {
  let assert V(_, _, _, children) = root
  use children <- on.ok(children |> list.try_map(map_chapter))
  Ok(V(..root, children: children))
}

fn transform_factory(_: InnerParam) -> infra.DesugarerTransform {
  at_root
  |> n2t.at_root_2_desugarer_transform
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(param)
}

type Param =
  Nil

type InnerParam =
  Nil

pub const name = "lbp_generate_breadcrumbs"

fn desugarer_blame(line_no: Int) {
  bl.Des([], name, line_no)
}

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
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
