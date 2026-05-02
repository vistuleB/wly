import blame
import gleam/list
import gleam/option
import gleam/regexp
import gleam/string.{inspect as ins}
import infrastructure.{type Desugarer, Desugarer, type DesugarerTransform, type DesugaringError, DesugaringError} as infra
import nodemaps_2_desugarer_transforms as n2t
import vxml.{type VXML, T, Line}

fn nodemap(
  vxml: VXML,
  from_re: regexp.Regexp,
  to: String,
) -> VXML {
  case vxml {
    T(blame, lines) -> {
      let new_lines =
        list.map(lines, fn(line) {
          Line(..line, content: regexp.replace(from_re, line.content, to))
        })
      T(blame, new_lines)
    }
    _ -> vxml
  }
}

fn nodemap_factory(inner: InnerParam) -> n2t.OneToOneNoErrorNodemap {
  let #(re, to) = inner
  nodemap(_, re, to)
}

fn transform_factory(inner: InnerParam, outside: List(String)) -> DesugarerTransform {
  nodemap_factory(inner)
  |> n2t.one_to_one_no_error_nodemap_2_desugarer_transform_with_forbidden(outside)
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  let #(from, to) = param
  case regexp.from_string(from) {
    Ok(re) -> Ok(#(re, to))
    Error(_) -> Error(DesugaringError(blame.no_blame, "Invalid regex: " <> from))
  }
}

type Param = #(String, String)
//             ↖       ↖
//             from    to
type InnerParam = #(regexp.Regexp, String)

pub const name = "replace_string__outside"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// replaces occurrences of a regex pattern with a
/// replacement string in every line of every text node,
/// while avoiding subtrees rooted at tags appearing 
/// in the second argument
pub fn constructor(param: Param, outside: List(String)) -> Desugarer {
  Desugarer(
    name: name,
    stringified_param: option.Some(ins(param)),
    stringified_outside: option.Some(ins(outside)),
    transform: case param_to_inner_param(param) {
      Error(error) -> fn(_) { Error(error) }
      Ok(inner) -> transform_factory(inner, outside)
    },
  )
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
fn assertive_tests_data() -> List(infra.AssertiveTestDataWithOutside(Param)) {
  [
    infra.AssertiveTestDataWithOutside(
      param: #("``", "“"),
      outside: ["keep_out"],
      source: "
                <> root
                  <>
                    'This is ``backticked``'
                  <> keep_out
                    <>
                      'This is ``backticked``'
                ",
      expected: "
                <> root
                  <>
                    'This is “backticked“'
                  <> keep_out
                    <>
                      'This is ``backticked``'
                ",
    ),
  ]
}

pub fn assertive_tests() {
  infra.assertive_test_collection_from_data_with_outside(name, assertive_tests_data(), constructor)
}
