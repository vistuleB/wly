import gleam/option
import gleam/string
import infrastructure.{type Desugarer, Desugarer, type DesugarerTransform, type DesugaringError} as infra
import nodemaps_2_desugarer_transforms as n2t
import vxml.{type VXML, V, T, Attr}
import blame as bl

fn nodemap(
  vxml: VXML,
) -> VXML {
  case vxml {
    V(_, "div", _, children) -> {
      case {
        infra.v_has_class(vxml, "theorem") ||
        infra.v_has_class(vxml, "numbered-exercise") ||
        infra.v_has_class(vxml, "numbered-title")
      } {
        True -> case children {
          [V(_, "span", _, span_children) as span, ..rest] -> {
            case infra.v_has_key_value(span, "class", "numbered-title") {
              True -> case span_children {
                [T(_, [one_line]), ..] -> {
                  let title = one_line.content |> string.trim
                  V(
                    desugarer_blame(25),
                    "Statement",
                    [
                      Attr(desugarer_blame(28), "title", "*" <> title <> "*"),
                    ],
                    rest,
                  )
                }
                _ -> vxml
              }
              False -> vxml
            }
          }
          _ -> vxml
        }
        False -> vxml
      }
    }
    _ -> vxml
  }
}

fn nodemap_factory(_inner: InnerParam) -> n2t.OneToOneNoErrorNodeMap {
  nodemap(_)
}

fn transform_factory(inner: InnerParam) -> DesugarerTransform {
  nodemap_factory(inner)
  |> n2t.one_to_one_no_error_nodemap_2_desugarer_transform()
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(param)
}

type Param = Nil
type InnerParam = Param

pub const name = "ii2_class_well_container_theorem_2_statement"
fn desugarer_blame(line_no: Int) { bl.Des([], name, line_no) }


// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// unwraps nodes with a certain tag when they
/// have a unique child of another designated tag
pub fn constructor() -> Desugarer {
  Desugarer(
    name: name,
    stringified_param: option.None,
    stringified_outside: option.None,
    transform: case param_to_inner_param(Nil) {
      Error(error) -> fn(_) { Error(error) }
      Ok(inner) -> transform_factory(inner)
    },
  )
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
fn assertive_tests_data() -> List(infra.AssertiveTestDataNoParam) {
  []
}

pub fn assertive_tests() {
  infra.assertive_test_collection_from_data_no_param(name, assertive_tests_data(), constructor)
}
