import desugaring/authoring
import desugaring/core.{type Desugarer, type DesugarerTransform}
import desugaring/nodemaps_2_transform as n2t
import gleam/list
import gleam/string
import vxml.{type Line, type VXML, Attr, Line, T, V}
import vxml/blame as bl

pub const name = "ti2_dominik_prompt_response"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Marks `$ ` lines as terminal commands and all other
/// lines as terminal output.
pub fn constructor() -> Desugarer {
  authoring.no_param_desugarer(
    name: name,
    transform: inner_param_to_transform(),
  )
}

const command_prefix = "$ "

const newline = T(
  bl.Des([], name, 27),
  [
    Line(bl.Des([], name, 29), ""),
    Line(bl.Des([], name, 30), ""),
  ],
)

fn span(line: Line, class: String, content: String) -> VXML {
  V(line.blame, "span", [Attr(desugarer_blame(38), "class", class)], [
    T(line.blame, [Line(line.blame, content)]),
  ])
}

fn line_to_elements(line: Line) -> List(VXML) {
  case string.starts_with(line.content, command_prefix) {
    True -> [
      span(line, "terminal-prompt", "$"),
      span(
        Line(bl.advance(line.blame, 1), line.content |> string.drop_start(1)),
        "terminal-prompt-content",
        line.content |> string.drop_start(1),
      ),
    ]
    False -> [span(line, "terminal-output", line.content)]
  }
}

fn nodemap(vxml: VXML) -> VXML {
  case vxml {
    V(blame, "pre", attrs, [T(_, lines)]) ->
      case core.v_has_key_val(vxml, "language", "dominik-prompt-response") {
        True -> {
          let children =
            lines
            |> list.map(line_to_elements)
            |> list.intersperse([newline])
            |> list.flatten

          V(
            blame,
            "pre",
            attrs
              |> core.attrs_delete("language")
              |> core.attrs_append_classes(
                desugarer_blame(77),
                "dominik-prompt-response",
              ),
            children,
          )
        }
        False -> vxml
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
                  language=dominik-prompt-response
                  class=listing
                  <>
                    '$ ls'
                    'IMG-1.jpg'
                    'IMG-2.jpg'
                    '$ pwd'
                    '/home/user/images'
                ",
      expected: "
                <> pre
                  class=listing dominik-prompt-response
                  <> span
                    class=terminal-prompt
                    <>
                      '$'
                  <> span
                    class=terminal-prompt-content
                    <>
                      ' ls'
                  <>
                    ''
                    ''
                  <> span
                    class=terminal-output
                    <>
                      'IMG-1.jpg'
                  <>
                    ''
                    ''
                  <> span
                    class=terminal-output
                    <>
                      'IMG-2.jpg'
                  <>
                    ''
                    ''
                  <> span
                    class=terminal-prompt
                    <>
                      '$'
                  <> span
                    class=terminal-prompt-content
                    <>
                      ' pwd'
                  <>
                    ''
                    ''
                  <> span
                    class=terminal-output
                    <>
                      '/home/user/images'
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
