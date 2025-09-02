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
    V(blame, "CodeBlock", _, [T(_, lines)]) -> {
      case infra.v_has_key_value(vxml, "language", "arbitrary-prompt-response") {
        True -> V(
          blame,
          "pre",
          [Attribute(desugarer_blame(86), "class", "well highlight")],
          process_lines(lines),
        )
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

pub const name = "ti3_parse_arbitrary_prompt_response_code_block"
fn desugarer_blame(line_no) {bl.Des([], name, line_no)}

type Param = Nil
type InnerParam = Nil

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// Processes CodeBlock elements with language=orange-comment
/// and converts them to pre elements with orange
/// comment highlighting for text after // markers
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
      source: "
                <> CodeBlock
                  language=orange-comment
                  <>
                    \"def mult(t,x):\"
                    \"    temp = 0 //= zero(x)\"
                    \"    for i in range(t):\"
                    \"        temp = add(temp,x) //= Comp(add, p_0, p2) (temp,i,x)\"
                    \"    return temp\"
                ",
      expected: "
                <> pre
                  <>
                    \"def mult(t,x):\"
                    \"    temp = 0 \"
                  <> span
                    class=orange-comment
                    <>
                      \"= zero(x)\"
                  <>
                    \"\"
                    \"    for i in range(t):\"
                    \"        temp = add(temp,x) \"
                  <> span
                    class=orange-comment
                    <>
                      \"= Comp(add, p_0, p2) (temp,i,x)\"
                  <>
                    \"\"
                    \"    return temp\"
                "
    ),
  ]
}

pub fn assertive_tests() {
  infra.assertive_test_collection_from_data_no_param(name, assertive_tests_data(), constructor)
}
