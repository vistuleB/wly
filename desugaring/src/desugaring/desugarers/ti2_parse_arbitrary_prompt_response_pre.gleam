import desugaring/authoring
import desugaring/core.{type Desugarer, type DesugarerTransform}
import desugaring/nodemaps_2_transform as n2t
import gleam/list
import gleam/result
import gleam/string
import vxml.{type Line, type VXML, Attr, Line, T, V}
import vxml/blame as bl

pub const name = "ti2_parse_arbitrary_prompt_response_pre"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Structures arbitrary prompt-response code blocks and
/// marks their prompts, responses, and terminal prefixes.
pub fn constructor() -> Desugarer {
  authoring.no_param_desugarer(
    name: name,
    transform: inner_param_to_transform(),
  )
}

const newline_t = T(
  bl.Des([], name, 26),
  [
    Line(bl.Des([], name, 28), ""),
    Line(bl.Des([], name, 29), ""),
  ],
)

const terminal_prompt = "user@home:~$"

const terminal_prompt_span = V(
  bl.Des([], name, 36),
  "span",
  [Attr(bl.Des([], name, 38), "class", "terminal-prompt")],
  [],
)

const terminal_prompt_content_span = V(
  bl.Des([], name, 43),
  "span",
  [Attr(bl.Des([], name, 45), "class", "terminal-prompt-content")],
  [],
)

const prompt_span = V(
  bl.Des([], name, 50),
  "span",
  [Attr(bl.Des([], name, 52), "class", "arbitrary-prompt")],
  [],
)

const response_span = V(
  bl.Des([], name, 57),
  "span",
  [Attr(bl.Des([], name, 59), "class", "arbitrary-response")],
  [],
)

fn line_2_t(line: Line) -> VXML {
  T(line.blame, [line])
}

fn elements_for_line(line: Line) -> List(VXML) {
  let #(before, after) =
    string.split_once(line.content, "<- ")
    |> result.unwrap(case string.starts_with(line.content, terminal_prompt) {
      False -> #(line.content, "")
      True -> #(
        terminal_prompt,
        string.drop_start(line.content, terminal_prompt |> string.length),
      )
    })
  let after_blame = bl.advance(line.blame, string.length(before) + 2)
  case before == terminal_prompt {
    False -> [
      prompt_span |> core.v_prepend_child(line_2_t(Line(line.blame, before))),
      response_span |> core.v_prepend_child(line_2_t(Line(after_blame, after))),
    ]
    True -> [
      terminal_prompt_span
        |> core.v_prepend_child(line_2_t(Line(line.blame, before))),
      terminal_prompt_content_span
        |> core.v_prepend_child(line_2_t(Line(after_blame, after))),
    ]
  }
}

fn process_lines(lines: List(Line)) -> List(VXML) {
  lines
  |> list.fold([], fn(acc, line) { [elements_for_line(line), ..acc] })
  |> list.reverse
  |> list.intersperse([newline_t])
  |> list.flatten
}

fn nodemap(vxml: VXML) -> VXML {
  case vxml {
    V(blame, "pre", attrs, [T(_, lines)]) -> {
      case core.v_has_key_val(vxml, "language", "arbitrary-prompt-response") {
        True -> {
          let children = process_lines(lines)
          V(
            blame,
            "pre",
            attrs
              |> core.attrs_delete("language")
              |> core.attrs_append_classes(
                desugarer_blame(112),
                "arbitrary-prompt-response",
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

fn desugarer_blame(line_no) {
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
                  language=arbitrary-prompt-response
                  <>
                    'user@home:~$ java TestRegex'
                    'Please enter a regular expression: <- (a+)(:a+)*'
                    'Enter words to be matched, one per line'
                    '<- aaaaa:aa:aaaa:a'
                    'true'
                    '<- aaa:aa:'
                    'false'
                ",
      expected: "
                <> pre
                  class=arbitrary-prompt-response
                  <> span
                    class=terminal-prompt
                    <>
                      'user@home:~$'
                  <> span
                    class=terminal-prompt-content
                    <>
                      ' java TestRegex'
                  <>
                    ''
                    ''
                  <> span
                    class=arbitrary-prompt
                    <>
                      'Please enter a regular expression: '
                  <> span
                    class=arbitrary-response
                    <>
                      '(a+)(:a+)*'
                  <>
                    ''
                    ''
                  <> span
                    class=arbitrary-prompt
                    <>
                      'Enter words to be matched, one per line'
                  <> span
                    class=arbitrary-response
                    <>
                      ''
                  <>
                    ''
                    ''
                  <> span
                    class=arbitrary-prompt
                    <>
                      ''
                  <> span
                    class=arbitrary-response
                    <>
                      'aaaaa:aa:aaaa:a'
                  <>
                    ''
                    ''
                  <> span
                    class=arbitrary-prompt
                    <>
                      'true'
                  <> span
                    class=arbitrary-response
                    <>
                      ''
                  <>
                    ''
                    ''
                  <> span
                    class=arbitrary-prompt
                    <>
                      ''
                  <> span
                    class=arbitrary-response
                    <>
                      'aaa:aa:'
                  <>
                    ''
                    ''
                  <> span
                    class=arbitrary-prompt
                    <>
                      'false'
                  <> span
                    class=arbitrary-response
                    <>
                      ''
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
