import gleam/list
import gleam/option
import gleam/string
import infrastructure.{type Desugarer, Desugarer, type DesugarerTransform, type DesugaringError} as infra
import nodemaps_2_desugarer_transforms as n2t
import vxml.{type TextLine, type VXML, Attribute, TextLine, T, V}
import blame as bl

const newline_t =
  T(
    bl.Des([], name, 11),
    [
      TextLine(bl.Des([], name, 13), ""),
      TextLine(bl.Des([], name, 14), ""),
    ]
  )

type PythonPromptChunk {
  PromptLine(TextLine)
  OkResponseLines(List(TextLine))
  ErrorResponseLines(List(TextLine))
}

fn python_prompt_chunk_to_vxmls(
  chunk: PythonPromptChunk,
) -> List(VXML) {
  case chunk {
    PromptLine(line) -> {
      [
        V(
          desugarer_blame(31),
          "span",
          [Attribute(desugarer_blame(33), "class", "python-prompt-carets")],
          [
            T(
              line.blame,
              [TextLine(line.blame, ">>>")]
            )
          ]
        ),
        V(
          desugarer_blame(42),
          "span",
          [Attribute(desugarer_blame(44), "class", "python-prompt-content")],
          [
            T(
              bl.advance(line.blame, 3),
              [TextLine(bl.advance(line.blame, 3), line.content |> string.drop_start(3))]
            )
          ]
        )
      ]
    }
    OkResponseLines(lines) -> {
      [
        V(
          desugarer_blame(57),
          "span",
          [Attribute(desugarer_blame(59), "class", "python-prompt-ok-response")],
          [
            T(
              lines |> infra.lines_first_blame,
              lines
            )
          ]
        )
      ]
    }
    ErrorResponseLines(lines) -> {
      [
        V(
          desugarer_blame(72),
          "span",
          [Attribute(desugarer_blame(74), "class", "python-prompt-error-response")],
          [
            T(
              lines |> infra.lines_first_blame,
              lines
            )
          ]
        )
      ]
    }
  }
}

fn process_python_prompt_lines(lines: List(TextLine)) -> List(PythonPromptChunk) {
  lines
  |> infra.either_or_misceginator(fn(line) {
    string.starts_with(line.content, ">>>")
  })
  |> infra.regroup_ors_no_empty_lists
  |> list.map(fn(either_bc_or_list_bc) {
    case either_bc_or_list_bc {
      infra.Either(line) -> PromptLine(line)
      infra.Or(list_bc) -> case infra.lines_contain(list_bc, "SyntaxError:") {
        True -> ErrorResponseLines(list_bc)
        False -> OkResponseLines(list_bc)
      }
    }
  })
}

fn nodemap(
  vxml: VXML,
) -> VXML {
  case vxml {
    V(blame, "pre", attrs, [T(_, lines)]) -> {
      case infra.v_has_key_value(vxml, "language", "python-prompt") {
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
            |> infra.attributes_delete("language")
            |> infra.append_to_class_attribute(desugarer_blame(127), "python-prompt"),
            children,
          )
        }

        _ -> vxml
      }
    }
    _ -> vxml
  }
}

fn nodemap_factory(_inner: InnerParam) -> n2t.OneToOneNoErrorNodeMap {
  nodemap
}

fn transform_factory(inner: InnerParam) -> DesugarerTransform {
  nodemap_factory(inner)
  |> n2t.one_to_one_no_error_nodemap_2_desugarer_transform
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(param)
}

pub const name = "ti3_parse_python_prompt_pre"
fn desugarer_blame(line_no: Int) {bl.Des([], name, line_no)}

type Param = Nil
type InnerParam = Param

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// Processes CodeBlock elements with
/// language=python-prompt and converts them to pre
/// elements with proper span highlighting for
/// prompts, responses, and errors
pub fn constructor() -> Desugarer {
  Desugarer(
    name: name,
    stringified_param: option.None,
    stringified_outside: option.None,
    transform: case param_to_inner_param(Nil) {
      Error(e) -> fn(_) { Error(e) }
      Ok(inner) -> transform_factory(inner)
    },
  )
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
fn assertive_tests_data() -> List(infra.AssertiveTestDataNoParam) {
  [
    infra.AssertiveTestDataNoParam(
      source: "
                <> pre
                  language=python-prompt
                  <>
                    \">>> (6 + 8) * 3\"
                    \"42\"
                    \">>> (2 * 3))\"
                    \"  File \\\"<stdin>\\\", line 1\"
                    \"    (2 * 3))\"
                    \"           ^\"
                    \"SyntaxError: unmatched ')'\"
                ",
      expected: "
                <> pre
                  class=python-prompt
                  <> span
                    class=python-prompt-carets
                    <>
                      \">>>\"
                  <> span
                    class=python-prompt-content
                    <>
                      \" (6 + 8) * 3\"
                  <>
                    \"\"
                    \"\"
                  <> span
                    class=python-prompt-ok-response
                    <>
                      \"42\"
                  <>
                    \"\"
                    \"\"
                  <> span
                    class=python-prompt-carets
                    <>
                      \">>>\"
                  <> span
                    class=python-prompt-content
                    <>
                      \" (2 * 3))\"
                  <>
                    \"\"
                    \"\"
                  <> span
                    class=python-prompt-error-response
                    <>
                      \"  File \\\"<stdin>\\\", line 1\"
                      \"    (2 * 3))\"
                      \"           ^\"
                      \"SyntaxError: unmatched ')'\"
                "
    ),
  ]
}

pub fn assertive_tests() {
  infra.assertive_test_collection_from_data_no_param(name, assertive_tests_data(), constructor)
}
