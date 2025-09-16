import gleam/list
import gleam/option.{None}
import gleam/string
import gleam/result
import infrastructure.{type Desugarer, Desugarer, type DesugarerTransform, type DesugaringError} as infra
import nodemaps_2_desugarer_transforms as n2t
import vxml.{type TextLine, type VXML, Attribute, TextLine, T, V}
import blame as bl

const newline_t =
  T(
    bl.Des([], name, 12),
    [
      TextLine(bl.Des([], name, 14), ""),
      TextLine(bl.Des([], name, 15), ""),
    ]
  )

const terminal_prompt = "user@home:~$"

const prompt =
  V(
    bl.Des([], name, 22),
    "span",
    [Attribute(bl.Des([], name, 18), "class", "arbitrary-prompt")],
    [],
  )

const terminal_prompt_span =
  V(
    bl.Des([], name, 31),
    "span",
    [Attribute(bl.Des([], name, 18), "class", "terminal-prompt")],
    [],
  )

const response =
  V(
    bl.Des([], name, 30),
    "span",
    [Attribute(bl.Des([], name, 18), "class", "arbitrary-response")],
    [],
  )

fn line_2_t(line: TextLine) -> VXML {
  T(line.blame, [line])
}

fn elements_for_line(line: TextLine) -> List(VXML) {
  let #(before, after) =
    string.split_once(line.content, "<- ")
    |> result.unwrap(
      case string.starts_with(line.content, terminal_prompt) {
        False -> #(line.content, "")
        True -> #(terminal_prompt, string.drop_start(line.content, terminal_prompt |> string.length))
      }
    )
  let after_blame = bl.advance(line.blame, string.length(before) + 2)
  let prompt = case before == terminal_prompt {
    False -> prompt |> infra.v_prepend_child(line_2_t(TextLine(line.blame, before)))
    True -> terminal_prompt_span |> infra.v_prepend_child(line_2_t(TextLine(line.blame, before)))
  }
  let response = response |> infra.v_prepend_child(line_2_t(TextLine(after_blame, after)))
  [prompt, response]
}

fn process_lines(
  lines: List(TextLine),
) -> List(VXML) {
  lines
  |> list.fold([], fn(acc, line) {[elements_for_line(line), ..acc]})
  |> list.reverse
  |> list.intersperse([newline_t])
  |> list.flatten
}

fn nodemap(
  vxml: VXML,
) -> VXML {
  case vxml {
    V(blame, "pre", attrs, [T(_, lines)]) -> {
      case infra.v_has_key_value(vxml, "language", "arbitrary-prompt-response") {
        True -> {
          let children = process_lines(lines)
          V(
            blame,
            "pre",
            attrs
            |> infra.attributes_delete("language")
            |> infra.attributes_append_classes(desugarer_blame(90), "arbitrary-prompt-response"),
            children,
          )
        }
        _ -> vxml
      }
    }
    _ -> vxml
  }
}

fn nodemap_factory(_: InnerParam) -> n2t.OneToOneNoErrorNodeMap {
  nodemap(_)
}

fn transform_factory(inner: InnerParam) -> DesugarerTransform {
  nodemap_factory(inner)
  |> n2t.one_to_one_no_error_nodemap_2_desugarer_transform
}

fn param_to_inner_param(_param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(Nil)
}

pub const name = "ti3_parse_arbitrary_prompt_response_pre"
fn desugarer_blame(line_no) { bl.Des([], name, line_no) }

type Param = Nil
type InnerParam = Nil

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// Processes pre elements with language=arbitrary-prompt-response
/// and...
pub fn constructor() -> Desugarer {
  Desugarer(
    name,
    None,
    None,
    case param_to_inner_param(Nil) {
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
      source:   "
                <> CodeBlock
                  language=arbitrary-prompt-response
                  <>
                    \"user@home:~$ java TestRegex\"
                    \"Please enter a regular expression: <- (a+)(:a+)*\"
                    \"Enter words to be matched, one per line\"
                    \"<- aaaaa:aa:aaaa:a\"
                    \"true\"
                    \"<- aaa:aa:\"
                    \"false\"
                ",
      expected: "
                <> pre
                  class=well highlight
                  <> span
                    class=terminal-prompt
                    <>
                      \"user@home:~$\"
                  <> span
                    class=arbitrary-response
                    <>
                      \" java TestRegex\"
                  <>
                    \"\"
                    \"\"
                  <> span
                    class=arbitrary-prompt
                    <>
                      \"Please enter a regular expression: \"
                  <> span
                    class=arbitrary-response
                    <>
                      \"(a+)(:a+)*\"
                  <>
                    \"\"
                    \"\"
                  <> span
                    class=arbitrary-prompt
                    <>
                      \"Enter words to be matched, one per line\"
                  <> span
                    class=arbitrary-response
                    <>
                      \"\"
                  <>
                    \"\"
                    \"\"
                  <> span
                    class=arbitrary-prompt
                    <>
                      \"\"
                  <> span
                    class=arbitrary-response
                    <>
                      \"aaaaa:aa:aaaa:a\"
                  <>
                    \"\"
                    \"\"
                  <> span
                    class=arbitrary-prompt
                    <>
                      \"true\"
                  <> span
                    class=arbitrary-response
                    <>
                      \"\"
                  <>
                    \"\"
                    \"\"
                  <> span
                    class=arbitrary-prompt
                    <>
                      \"\"
                  <> span
                    class=arbitrary-response
                    <>
                      \"aaa:aa:\"
                  <>
                    \"\"
                    \"\"
                  <> span
                    class=arbitrary-prompt
                    <>
                      \"false\"
                  <> span
                    class=arbitrary-response
                    <>
                      \"\"
                "
    ),
  ]
}

pub fn assertive_tests() {
  infra.assertive_test_collection_from_data_no_param(name, assertive_tests_data(), constructor)
}
