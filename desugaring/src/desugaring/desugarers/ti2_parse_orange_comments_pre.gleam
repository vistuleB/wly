import desugaring/authoring
import desugaring/core.{type Desugarer, type DesugarerTransform}
import desugaring/nodemaps_2_transform as n2t
import gleam/list
import gleam/string
import on
import vxml.{type Line, type VXML, Attr, Line, T, V}
import vxml/blame as bl

pub const name = "ti2_parse_orange_comments_pre"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Highlights comment text following `//` in code blocks
/// configured with the `orange-comments` language.
pub fn constructor() -> Desugarer {
  authoring.no_param_desugarer(
    name: name,
    transform: inner_param_to_transform(),
  )
}

const t_1_empty_line = T(bl.Des([], name, 25), [Line(bl.Des([], name, 25), "")])

const orange = V(
  bl.Des([], name, 28),
  // "functions can only be called within other functions..."
  "span",
  [Attr(bl.Des([], name, 31), "class", "actual-orange-comment")],
  [],
)

fn line_to_text_node(line: Line) -> VXML {
  T(line.blame, [line])
}

fn elements_for_line(line: Line) -> List(VXML) {
  case string.split_once(line.content, "//") {
    Error(_) -> [line_to_text_node(line)]
    Ok(#(before, after)) -> {
      let after_blame = bl.advance(line.blame, string.length(before) + 2)
      let before = line_to_text_node(Line(line.blame, before))
      let orange =
        orange
        |> core.v_prepend_child(line_to_text_node(Line(after_blame, after)))
      [before, orange, t_1_empty_line]
    }
  }
}

fn process_orange_comment_lines(lines: List(Line)) -> List(VXML) {
  lines
  |> list.fold([], fn(acc, line) { core.pour(elements_for_line(line), acc) })
  |> list.reverse
  |> core.plain_concatenation_in_list
}

fn nodemap(vxml: VXML) -> VXML {
  case vxml {
    V(blame, "pre", attrs, [T(_, lines)]) -> {
      use language <- on.eager_none_some(
        core.v_val_of_first_attr_with_key(vxml, "language"),
        vxml,
      )

      case language == "orange-comments" {
        True -> {
          let children = process_orange_comment_lines(lines)

          V(
            blame,
            "pre",
            attrs
              |> core.attrs_delete("language")
              |> core.attrs_append_classes(
                desugarer_blame(78),
                "orange-comments",
              ),
            children,
          )
        }
        _ -> vxml
      }
    }
    _ -> vxml
  }
}

fn inner_param_to_transform() -> DesugarerTransform {
  let nodemap: n2t.OneToOneNoErrorNodemap = nodemap
  nodemap
  |> n2t.one_to_one_no_error_nodemap_2_desugarer_transform
}

fn desugarer_blame(line_no: Int) {
  bl.Des([], name, line_no)
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
fn assertive_tests_data() -> List(core.AssertiveTestDataNoParam) {
  [
    core.AssertiveTestDataNoParam(
      source: "
                <> pre
                  language=orange-comments
                  <>
                    'def mult(t,x):'
                    '    temp = 0 //= zero(x)'
                    '    for i in range(t):'
                    '        temp = add(temp,x) //= Comp(add, p_0, p2) (temp,i,x)'
                    '    return temp'
                ",
      expected: "
                <> pre
                  class=orange-comments
                  <>
                    'def mult(t,x):'
                    '    temp = 0 '
                  <> span
                    class=actual-orange-comment
                    <>
                      '= zero(x)'
                  <>
                    ''
                    '    for i in range(t):'
                    '        temp = add(temp,x) '
                  <> span
                    class=actual-orange-comment
                    <>
                      '= Comp(add, p_0, p2) (temp,i,x)'
                  <>
                    ''
                    '    return temp'
                ",
    ),
  ]
}

pub fn assertive_tests() {
  core.assertive_test_collection_from_data_no_param(
    name,
    assertive_tests_data(),
    constructor,
  )
}
