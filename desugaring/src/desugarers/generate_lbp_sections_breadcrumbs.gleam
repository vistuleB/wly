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
  use last <- on.error_ok(
    list.last(nodes),
    fn(_) { nodes }
  )

  use <- on.false_true(
    infra.is_text_node(last),
    fn(){
      // in case last node is a V node . call remove period recursvaly on it's children
      let assert V(b, t, a, children) = last
      list.flatten([
        list.take(nodes, list.length(nodes) - 1),
        [V(b, t, a, remove_period(children))]
      ])
    }
  )

  let assert T(b, lines) = last
  use last_line <- on.error_ok(
    list.last(lines),
    fn(_) { nodes }
  )
  // some Text nodes ends with "" . so it should be ignored and remove_period on nodes without last one
  use <- on.false_true(
    last_line.content != "",
    fn() {
      list.take(nodes, list.length(nodes) - 1)
      |> remove_period()
    },
  )

  let new_last_line = case string.ends_with(last_line.content, ".") {
    True -> {
      Line(last_line.blame, string.drop_end(last_line.content, 1))
    }
    False -> last_line
  }
  // replace last Line
  let new_t = T(b, list.flatten([
    list.take(lines, list.length(lines) - 1),
    [new_last_line]
  ]))
  // replace last node
  list.flatten([
    list.take(nodes, list.length(nodes) - 1),
    [new_t]
  ])
}

fn small_caps_t(t: VXML) -> VXML{
  let assert T(b, contents) = t
  contents
  |> list.map(fn(line){
    Line(line.blame, string.lowercase(line.content))
  })
  |> T(b, _)
}

fn small_caps_nodes(nodes: List(VXML), result: List(VXML)) -> List(VXML) {
  case nodes {
    [] -> result |> list.reverse
    [first, ..rest] -> {
      case first {
        T(_, _) -> small_caps_nodes(rest, [small_caps_t(first), ..result])
        V(b, t, a, children) -> small_caps_nodes(rest, [
          V(b, t, a, small_caps_nodes(children, [])),
          ..result
        ])
      }
    }
  }
}

fn transform_children(children: List(VXML)) -> List(VXML){
  children
  |> small_caps_nodes([])
  |> remove_period()
}

fn construct_breadcrumb(children: List(VXML), target_id: String, index: Int) -> VXML {
  let link = V(
    desugarer_blame(99),
    "InChapterLink",
    [Attr(desugarer_blame(101), "href", "?id=" <> target_id)],
    children
  )

  V(
    desugarer_blame(106),
    "BreadcrumbItem",
    [
      Attr(desugarer_blame(109), "class", "breadcrumb"),
      Attr(desugarer_blame(110), "id", "breadcrumb-" <> ins(index)),
    ],
    [
      link
    ],
  )
}

fn map_section(section: VXML, index: Int) -> Result(VXML, DesugaringError) {
  case infra.v_get_children(section) {
    [V(_, "BreadcrumbTitle", _, children), ..] -> {
      children
      |> transform_children
      |> construct_breadcrumb("section-" <> ins(index + 1), index)
      |> Ok
    }
    _ -> Error(DesugaringError(section.blame, "Section must have a BreadcrumbTitle as first child"))
  }
}

fn generate_sections_list(sections: List(VXML), exercises: List(VXML)) -> Result(VXML, DesugaringError) {
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
    _ -> panic as "We don't have more than one exercises section"
  }

  Ok(V(
    desugarer_blame(150),
    "SectionsBreadcrumbs",
    [],
    list.flatten([sections_nodes, exercises_node])
  ))
}

fn map_chapter(child: VXML) -> Result(VXML, DesugaringError) {
  case child {
    V(b, "Chapter", a, children) -> {
      let sections = infra.v_children_with_tag(child, "Section")
      let exercises = infra.v_children_with_tag(child, "Exercises")
      use sections_ul <- on.ok(generate_sections_list(sections, exercises))
      Ok(V(b, "Chapter", a, [sections_ul, ..children]))
    }
    V(b, "Bootcamp", a, children) -> {
      let sections = infra.v_children_with_tag(child, "Section")
      let exercises = infra.v_children_with_tag(child, "Exercises")
      use sections_ul <- on.ok(generate_sections_list(sections, exercises))
      Ok(V(b, "Bootcamp", a, [sections_ul, ..children]))
    }
    _ -> Ok(child)
  }
}

fn at_root(root: VXML) -> Result(VXML, DesugaringError) {
  let assert V(_, _, _, children) = root
  use children <- on.ok(children |> list.try_map(map_chapter))
  Ok(V(..root, children: children))
}

fn transform_factory(_: InnerParam) -> DesugarerTransform {
  at_root
  |> n2t.at_root_2_desugarer_transform
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(param)
}

type Param = Nil
type InnerParam = Nil

pub const name = "generate_lbp_sections_breadcrumbs"
fn desugarer_blame(line_no: Int) { bl.Des([], name, line_no) }

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
pub fn constructor(param: Param) -> Desugarer {
  Desugarer(
    name: name,
    stringified_param: option.None,
    stringified_outside: option.None,
    transform: case param_to_inner_param(param) {
      Error(error) -> fn(_) { Error(error) }
      Ok(inner) -> transform_factory(inner)
    },
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
