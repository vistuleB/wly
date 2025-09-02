import gleam/dict.{type Dict}
import gleam/list
import gleam/option
import gleam/string.{inspect as ins}
import infrastructure.{type Desugarer, Desugarer, type DesugarerTransform, type DesugaringError} as infra
import nodemaps_2_desugarer_transforms as n2t
import vxml.{type VXML, TextLine, T, V}
import blame.{type Blame} as bl

fn substitute_blames_in(node: VXML, new_blame: Blame) -> VXML {
  let assert T(_, lines) = node
  T(
    new_blame,
    list.map(lines, fn(line) {
      TextLine(new_blame, line.content)
    }),
  )
}

fn last_line_concatenate_with_first_line(node1: VXML, node2: VXML) -> VXML {
  let assert T(blame1, lines1) = node1
  let assert T(_, lines2) = node2

  let assert [TextLine(blame_last, content_last), ..other_lines1] =
    lines1 |> list.reverse
  let assert [TextLine(_, content_first), ..other_lines2] = lines2

  T(
    blame1,
    list.flatten([
      other_lines1 |> list.reverse,
      [TextLine(blame_last, content_last <> content_first)],
      other_lines2,
    ]),
  )
}

fn nodemap(
  node: VXML,
  inner: InnerParam,
) -> Result(VXML, DesugaringError) {
  case node {
    T(_, _) -> Ok(node)
    V(blame, tag, attrs, children) -> {
      case dict.get(inner, tag) {
        Error(Nil) -> Ok(node)
        Ok(#(v1, v2)) -> {
          let new_children =
            list.map(children, fn(child) {
              case child {
                V(_, _, _, _) -> child
                T(blame, _) -> {
                  substitute_blames_in(v1, blame)
                  |> last_line_concatenate_with_first_line(child)
                  |> last_line_concatenate_with_first_line(substitute_blames_in(
                    v2,
                    blame,
                  ))
                }
              }
            })
          Ok(V(blame, tag, attrs, new_children))
        }
      }
    }
  }
}

fn nodemap_factory(inner: InnerParam) -> n2t.OneToOneNodeMap {
  nodemap(_, inner)
}

fn transform_factory(inner: InnerParam) -> DesugarerTransform {
  n2t.one_to_one_nodemap_2_desugarer_transform(nodemap_factory(inner))
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  param
  |> list.map(fn(tuple) {
    let #(t1, t2, tag) = tuple
    let contents1 = string.split(t1, "\n")
    let contents2 = string.split(t2, "\n")
    let v1 =
      T(
        desugarer_blame(85),
        list.map(contents1, fn(content) {
          TextLine(desugarer_blame(87), content)
        }),
      )
    let v2 =
      T(
        desugarer_blame(92),
        list.map(contents2, fn(content) {
          TextLine(desugarer_blame(94), content)
        }),
      )
    #(tag, #(v1, v2))
  })
  |> dict.from_list
  |> Ok
}

type Param =
  List(#(String, String, String))
//       ↖       ↖       ↖
//       text    text    parent
//       to      to      tag
//       prepend append

type InnerParam =
  Dict(String, #(VXML, VXML))

pub const name = "prepend_append_to_text_children_of"
fn desugarer_blame(line_no: Int) {bl.Des([], name, line_no)}

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// prepends and appends text to all text children
/// of specified tags
pub fn constructor(param: Param) -> Desugarer {
  Desugarer(
    name: name,
    stringified_param: option.Some(ins(param)),
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
