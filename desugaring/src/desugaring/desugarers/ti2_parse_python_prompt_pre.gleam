import desugaring/authoring
import desugaring/core.{type Desugarer, type DesugarerTransform}
import desugaring/nodemaps_2_transform as n2t
import either_or as eo
import gleam/list
import gleam/string
import vxml.{type Line, type VXML, Attr, Line, T, V}
import vxml/blame as bl

pub const name = "ti2_parse_python_prompt_pre"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Structures Python prompt code blocks and highlights
/// prompts, responses, and errors.
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

const terminal_prompt_length = 12

type PythonPromptChunk {
  TerminalPrompt(Line)
  PromptLine(Line)
  OkResponseLines(List(Line))
  ErrorResponseLines(List(Line))
}

fn python_prompt_chunk_to_vxmls(chunk: PythonPromptChunk) -> List(VXML) {
  case chunk {
    TerminalPrompt(line) -> {
      let z = terminal_prompt_length
      [
        V(
          desugarer_blame(50),
          "span",
          [Attr(desugarer_blame(52), "class", "terminal-prompt")],
          [T(line.blame, [Line(line.blame, terminal_prompt)])],
        ),
        V(
          desugarer_blame(56),
          "span",
          [Attr(desugarer_blame(58), "class", "terminal-prompt-content")],
          [
            T(bl.advance(line.blame, z), [
              Line(
                bl.advance(line.blame, z),
                line.content |> string.drop_start(z),
              ),
            ]),
          ],
        ),
      ]
    }
    PromptLine(line) -> {
      [
        V(
          desugarer_blame(73),
          "span",
          [Attr(desugarer_blame(75), "class", "python-prompt-carets")],
          [T(line.blame, [Line(line.blame, ">>>")])],
        ),
        V(
          desugarer_blame(79),
          "span",
          [Attr(desugarer_blame(81), "class", "python-prompt-content")],
          [
            T(bl.advance(line.blame, 3), [
              Line(
                bl.advance(line.blame, 3),
                line.content |> string.drop_start(3),
              ),
            ]),
          ],
        ),
      ]
    }
    OkResponseLines(lines) -> {
      [
        V(
          desugarer_blame(96),
          "span",
          [Attr(desugarer_blame(98), "class", "python-prompt-ok-response")],
          [T(lines |> core.lines_first_blame, lines)],
        ),
      ]
    }
    ErrorResponseLines(lines) -> {
      [
        V(
          desugarer_blame(106),
          "span",
          [Attr(desugarer_blame(108), "class", "python-prompt-error-response")],
          [T(lines |> core.lines_first_blame, lines)],
        ),
      ]
    }
  }
}

fn process_python_prompt_lines(lines: List(Line)) -> List(PythonPromptChunk) {
  lines
  |> eo.discriminate(fn(line) {
    string.starts_with(line.content, ">>>")
    || string.starts_with(line.content, terminal_prompt)
  })
  |> eo.group_ors
  |> list.map(fn(either_bc_or_list_bc) {
    case either_bc_or_list_bc {
      eo.Either(line) -> {
        case string.starts_with(line.content, ">>>") {
          True -> PromptLine(line)
          False -> TerminalPrompt(line)
        }
      }
      eo.Or(list_bc) ->
        case core.lines_contain(list_bc, "SyntaxError:") {
          True -> ErrorResponseLines(list_bc)
          False -> OkResponseLines(list_bc)
        }
    }
  })
}

fn nodemap(vxml: VXML) -> VXML {
  case vxml {
    V(blame, "pre", attrs, [T(_, lines)]) -> {
      case core.v_has_key_val(vxml, "language", "python-prompt") {
        True -> {
          let children =
            lines
            |> process_python_prompt_lines
            |> list.map(python_prompt_chunk_to_vxmls)
            |> list.intersperse([newline_t])
            |> list.flatten

          V(
            blame,
            "pre",
            attrs
              |> core.attrs_delete("language")
              |> core.attrs_append_classes(
                desugarer_blame(158),
                "python-prompt",
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
                            language=python-prompt
                            <>
                              '>>> (6 + 8) * 3'
                              '42'
                              '>>> (2 * 3))'
                              '  File '<stdin>', line 1'
                              '    (2 * 3))'
                              '           ^'
                              'SyntaxError: unmatched ')''
                ",
      expected: "
                          <> pre
                            class=python-prompt
                            <> span
                              class=python-prompt-carets
                              <>
                                '>>>'
                            <> span
                              class=python-prompt-content
                              <>
                                ' (6 + 8) * 3'
                            <>
                              ''
                              ''
                            <> span
                              class=python-prompt-ok-response
                              <>
                                '42'
                            <>
                              ''
                              ''
                            <> span
                              class=python-prompt-carets
                              <>
                                '>>>'
                            <> span
                              class=python-prompt-content
                              <>
                                ' (2 * 3))'
                            <>
                              ''
                              ''
                            <> span
                              class=python-prompt-error-response
                              <>
                                '  File '<stdin>', line 1'
                                '    (2 * 3))'
                                '           ^'
                                'SyntaxError: unmatched ')''
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
