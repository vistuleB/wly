import gleam/list
import gleam/option.{None}
import infrastructure.{type Desugarer, Desugarer, type DesugarerTransform, type DesugaringError} as infra
import nodemaps_2_desugarer_transforms as n2t
import vxml.{type VXML, T, V, TextLine}
import blame as bl

const newline_t =
  T(
    bl.Des([], name, 11),
    [
      TextLine(bl.Des([], name, 13), ""),
      TextLine(bl.Des([], name, 14), ""),
    ]
  )

fn nodemap(
  vxml: VXML,
) -> VXML {
  case vxml {
    V(_, "pre", _, children) -> {
      let children = list.map(
        children,
        fn(c) {
          case c {
            V(_, "br", _, _) -> {
              newline_t
            }
            _ -> c
          }
        }
      )
      |> infra.last_to_first_concatenation
      V(..vxml, children: children)
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

pub const name = "normalize_br_in_pre"

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
