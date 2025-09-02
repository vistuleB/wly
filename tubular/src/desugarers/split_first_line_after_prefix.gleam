import gleam/option
import gleam/string.{inspect as ins}
import infrastructure.{type Desugarer, Desugarer, type DesugarerTransform, type DesugaringError} as infra
import nodemaps_2_desugarer_transforms as n2t
import vxml.{type VXML, V, T, TextLine}
import blame as bl

fn do_it(
  t: VXML,
  prefix: String,
  prefix_length: Int,
) -> VXML {
  let assert T(blame, [first, ..rest]) = t
  case string.starts_with(first.content, prefix) {
    False -> t
    True -> {
      let end = string.drop_start(first.content, prefix_length)
      case end == "" {
        True -> t
        False -> {
          let trimmed_end = string.trim_start(end)
          case trimmed_end == "" {
            True -> T(
              blame,
              [
                TextLine(first.blame, prefix),
                ..rest
              ]
            )
            False -> {
              let amt_trimmed = string.length(end) - string.length(trimmed_end)
              let scnd_blame = bl.advance(first.blame, amt_trimmed)
              T(
                blame,
                [
                  TextLine(first.blame, prefix),
                  TextLine(scnd_blame, trimmed_end),
                  ..rest,
                ]
              )
            }
          }
        }
      }
    }
  }
}

fn nodemap(
  vxml: VXML,
  inner: InnerParam,
) -> VXML {
  case vxml {
    V(_, tag, _, children) if tag == inner.0 -> {
      let children = children |> infra.t_map(do_it(_, inner.1, inner.2))
      V(..vxml, children: children)
    }
    _ -> vxml
  }
}

fn nodemap_factory(inner: InnerParam) -> n2t.OneToOneNoErrorNodeMap {
  nodemap(_, inner)
}

fn transform_factory(inner: InnerParam) -> DesugarerTransform {
  n2t.one_to_one_no_error_nodemap_2_desugarer_transform(nodemap_factory(inner))
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  #(param.0, param.1, string.length(param.1))
  |> Ok
}

type Param = #(String,        String)
//             ↖              ↖
//             tag            prefix
type InnerParam = #(String, String, Int)

pub const name = "split_first_line_after_prefix"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// inserts text at the beginning and end of a
/// specified tag
pub fn constructor(param: Param) -> Desugarer {
  Desugarer(
    name: name,
    stringified_param: option.Some(ins(param)),
    stringified_outside: option.None,
    transform: case param_to_inner_param(param) {
      Error(error) -> fn(_) { Error(error) }
      Ok(inner) -> transform_factory(inner)
    },
  )
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
fn assertive_tests_data() -> List(infra.AssertiveTestData(Param)) {
  []
}

pub fn assertive_tests() {
  infra.assertive_test_collection_from_data(name, assertive_tests_data(), constructor)
}
