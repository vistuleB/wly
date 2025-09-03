import gleam/list
import gleam/option.{None}
import gleam/string
import infrastructure.{type Desugarer, Desugarer, type DesugarerTransform, type DesugaringError} as infra
import nodemaps_2_desugarer_transforms as n2t
import vxml.{type TextLine, type VXML, Attribute, TextLine, T, V}
import blame as bl

const t_1_empty_line = T(
  bl.Des([], name, 11),
  [TextLine(bl.Des([], name, 12), "")]
)
const orange =
  V(
    bl.Des([], name, 16),
    "span",
    [Attribute(bl.Des([], name, 18), "class", "orange-comment")],
    [],
  )

fn line_2_t(line: TextLine) -> VXML {
  T(line.blame, [line])
}

fn elements_for_line(line: TextLine) -> List(VXML) {
  case string.split_once(line.content, "//") {
    Error(_) -> [line_2_t(line)]
    Ok(#(before, after)) -> {
      let after_blame = bl.advance(line.blame, string.length(before) + 2)
      let before = line_2_t(TextLine(line.blame, before))
      let orange = orange |> infra.v_prepend_child(line_2_t(TextLine(after_blame, after)))
      [before, orange, t_1_empty_line]
    }
  }
}

fn process_orange_comment_lines(
  lines: List(TextLine),
) -> List(VXML) {
  lines
  |> list.fold([], fn(acc, line) { infra.pour(elements_for_line(line), acc)})
  |> list.reverse
  |> infra.plain_concatenation_in_list
}

fn nodemap(
  vxml: VXML,
) -> VXML {
  case vxml {
    V(blame, "CodeBlock", _, [T(_, lines)]) -> {
      case infra.v_has_key_value(vxml, "language", "orange-comment") {
        True ->
          V(
            blame,
            "pre",
            [],
            process_orange_comment_lines(lines, ),
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

pub const name = "ti3_parse_orange_comment_code_block"

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
