import gleam/string.{inspect as ins}
import gleam/result
import gleam/list
import infrastructure.{
  type Desugarer,
  type DesugarerTransform,
  type DesugaringError,
  Desugarer,
  DesugaringError,
} as infra
import gleam/option
import vxml.{type VXML, V, T, Line, Attr}
import blame as bl
import nodemaps_2_desugarer_transforms as n2t
import on

fn remove_period(nodes: List(VXML)) -> List(VXML) {
  use last, head <- on.eager_empty_nonempty(
    nodes |> list.reverse,
    [],
  )

  let head = head |> list.reverse

  use <- on.false_true(
    infra.is_text_node(last),
    fn() {
      let assert V(_, _, _, children) = last
      list.append(head, [V(..last, children: remove_period(children))])
    }
  )

  use last <- on.eager_none_some(
    infra.t_super_trim_end_and_remove_ending_period(last),
    head,
  )

  list.append(head, [last])
}

fn lowercase_t(t: VXML) -> VXML{
  let assert T(b, contents) = t
  contents
  |> list.map(fn(line) { Line(..line, content: string.lowercase(line.content)) })
  |> T(b, _)
}

fn lowercase_vxml(
  node: VXML,
) -> VXML {
  case node {
    T(_, _) -> lowercase_t(node)
    V(_, _, _, children) -> V(
      ..node,
      children: list.map(children, lowercase_vxml)
    )
  }
}

fn cleanup_children(children: List(VXML)) -> List(VXML){
  children
  |> list.map(lowercase_vxml)
  |> remove_period
}

fn construct_breadcrumb(children: List(VXML), target_id: String, index: Int) -> VXML {
  V(
    desugarer_blame(68),
    "BreadcrumbItem",
    [Attr(desugarer_blame(70), "id", "breadcrumb-" <> ins(index))],
    [
      V(
        desugarer_blame(73),
        "InChapterLink",
        [Attr(desugarer_blame(75), "href", "?id=" <> target_id)],
        children |> cleanup_children,
      ),
    ]
  )
}

fn map_section(section: VXML, index: Int) -> Result(VXML, DesugaringError) {
  case infra.v_get_children(section) {
    [V(_, "BreadcrumbTitle", _, children), ..] -> Ok(construct_breadcrumb(children, "section-" <> ins(index + 1), index))
    _ -> Error(DesugaringError(section.blame, "Section must have a BreadcrumbTitle as first child"))
  }
}

fn generate_sections_list(
  sections: List(VXML),
  exercises: List(VXML),
) -> Result(VXML, DesugaringError) {
  use sections_nodes <- on.ok(
    list.index_map(sections, map_section)
    |> result.all
  )

  let exercises_node = case exercises {
    [] -> []
    [one] -> {
      [
        construct_breadcrumb(
          [T(one.blame, [Line(one.blame, "exercises")])],
          "exercises",
          list.length(sections_nodes)
        )
      ]
    }
    _ -> panic as "there should not be more than one exercises section"
  }

  Ok(V(
    desugarer_blame(113),
    "SectionsBreadcrumbs",
    [],
    list.flatten([sections_nodes, exercises_node])
  ))
}

fn remove_breadcrumb_title(
  vxml: VXML,
) -> VXML {
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
    V(b, tag, a, children) if tag == "Chapter" || tag == "Bootcamp" -> {
      let sections = infra.v_children_with_tag(child, "Section")
      let exercises = infra.v_children_with_tag(child, "Exercises")
      use sections_ul <- on.ok(generate_sections_list(sections, exercises))
      Ok(V(b, tag, a, [sections_ul, ..children |> list.map(remove_breadcrumb_title)]))
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

type Param = Nil
type InnerParam = Nil

pub const name = "generate_lbp_breadcrumbs"
fn desugarer_blame(line_no: Int) { bl.Des([], name, line_no) }

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
  infra.assertive_test_collection_from_data_no_param(name, assertive_tests_data(), constructor)
}
