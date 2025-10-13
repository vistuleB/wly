import gleam/list
import gleam/option.{None}
import gleam/string
import infrastructure.{type Desugarer, Desugarer, type DesugarerTransform, type DesugaringError} as infra
import nodemaps_2_desugarer_transforms as n2t
import vxml.{type Line, type VXML, Attribute, Line, T, V}
import blame as bl
import on

const t_1_empty_line = T(
  bl.Des([], name, 11),
  [Line(bl.Des([], name, 12), "")]
)

const orange =
  V(
    bl.Des([], name, 16), // "functions can only be called within other functions..."
    "span",
    [Attribute(bl.Des([], name, 18), "class", "actual-orange-comment")],
    [],
  )

fn line_2_t(line: Line) -> VXML {
  T(line.blame, [line])
}

fn elements_for_line(line: Line) -> List(VXML) {
  case string.split_once(line.content, "//") {
    Error(_) -> [line_2_t(line)]
    Ok(#(before, after)) -> {
      let after_blame = bl.advance(line.blame, string.length(before) + 2)
      let before = line_2_t(Line(line.blame, before))
      let orange = orange |> infra.v_prepend_child(line_2_t(Line(after_blame, after)))
      [before, orange, t_1_empty_line]
    }
  }
}

fn process_orange_comment_lines(
  lines: List(Line),
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
    V(blame, "pre", attrs, [T(_, lines)]) -> {
      use language <- on.none_some(
        infra.v_value_of_first_attribute_with_key(vxml, "language"),
        vxml,
      )

      case language == "orange-comments" {
        True -> {
          let children = process_orange_comment_lines(lines)

          V(
            blame,
            "pre",
            attrs
            |> infra.attributes_delete("language")
            |> infra.attributes_append_classes(desugarer_blame(67), "orange-comments"),
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
  nodemap
}

fn transform_factory(inner: InnerParam) -> DesugarerTransform {
  nodemap_factory(inner)
  |> n2t.one_to_one_no_error_nodemap_2_desugarer_transform
}

fn param_to_inner_param(_param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(Nil)
}

pub const name = "ti2_parse_orange_comments_pre"
fn desugarer_blame(line_no: Int) { bl.Des([], name, line_no) }

type Param = Nil
type InnerParam = Nil

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// processes CodeBlock elements with language=orange-comment
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
                <> pre
                  language=orange-comments
                  <>
                    \"def mult(t,x):\"
                    \"    temp = 0 //= zero(x)\"
                    \"    for i in range(t):\"
                    \"        temp = add(temp,x) //= Comp(add, p_0, p2) (temp,i,x)\"
                    \"    return temp\"
                ",
      expected: "
                <> pre
                  class=orange-comments
                  <>
                    \"def mult(t,x):\"
                    \"    temp = 0 \"
                  <> span
                    class=actual-orange-comment
                    <>
                      \"= zero(x)\"
                  <>
                    \"\"
                    \"    for i in range(t):\"
                    \"        temp = add(temp,x) \"
                  <> span
                    class=actual-orange-comment
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
