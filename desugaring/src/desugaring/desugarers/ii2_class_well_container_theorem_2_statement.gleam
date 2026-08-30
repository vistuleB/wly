import desugaring/authoring
import desugaring/core.{type Desugarer, type DesugarerTransform}
import desugaring/nodemaps_2_transform as n2t
import gleam/string
import vxml.{type VXML, T, V}

fn inner_param_to_transform(_: InnerParam) -> DesugarerTransform {
  let nodemap: n2t.OneToOneNoErrorNodemap = nodemap
  nodemap
  |> n2t.one_to_one_no_error_nodemap_2_desugarer_transform()
}

fn nodemap(vxml: VXML) -> VXML {
  case vxml {
    V(_, "div", _, children) -> {
      case
        {
          core.v_has_class(vxml, "theorem")
          || core.v_has_class(vxml, "numbered-exercise")
          || core.v_has_class(vxml, "numbered-title")
        }
      {
        True -> {
          case children {
            [V(_, "span", _, span_children) as span, ..rest] -> {
              case core.v_has_key_val(span, "class", "numbered-title") {
                True -> {
                  case span_children {
                    [T(_, [one_line]), ..] -> {
                      let title = one_line.content |> string.trim
                      let title = core.drop_suffix(title, ".")
                      let title = core.drop_suffix(title, ":")
                      let title = case title {
                        "Übungsaufgabe" -> "Exercise"
                        "Beobachtung" -> "Observation"
                        "Beispiel" -> "Example"
                        "Behauptung" -> "Claim"
                        "Algorithmus" -> "Algorithm"
                        "Theroem" -> "Theorem"
                        _ -> title
                      }
                      V(desugarer_blame(36), title, [], rest)
                    }
                    _ -> {
                      vxml
                    }
                  }
                }
                False -> vxml
              }
            }
            _ -> vxml
          }
        }
        False -> vxml
      }
    }
    _ -> vxml
  }
}

type Param =
  Nil

type InnerParam =
  Param

pub const name = "ii2_class_well_container_theorem_2_statement"

fn desugarer_blame(line_no: Int) {
  authoring.blame(name, line_no)
}

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
/// Converts II2 theorem-style well containers into
/// `Statement` elements while retaining their contents.
pub fn constructor() -> Desugarer {
  authoring.no_param_desugarer(
    name: name,
    transform: inner_param_to_transform(Nil),
  )
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
fn assertive_tests_data() -> List(core.AssertiveTestDataNoParam) {
  [
    core.AssertiveTestDataNoParam(
      source: "
                <> div
                  class=well container theorem
                  <> span
                    class=numbered-title
                    <>
                      'Theorem'
                  <>
                    'a child'
                ",
      expected: "
                <> Theorem
                  <>
                    'a child'
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
