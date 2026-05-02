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

fn transform_factory(inner: InnerParam) -> DesugarerTransform {
  nodemap_factory(inner)
  |> n2t.one_to_one_no_error_nodemap_2_desugarer_transform()
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

pub const name = "replace_string"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// replaces occurrences of a regex pattern with a
/// replacement string in every line of every text node
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
  [
    infra.AssertiveTestData(
      param: #("``", "“"),
      source: "
                <> root
                  <>
                    'This is ``backticked``'
                    'Another ``line`` with ``multiple``'
                ",
      expected: "
                <> root
                  <>
                    'This is “backticked“'
                    'Another “line“ with “multiple“'
                ",
    ),
  ]
}

pub fn assertive_tests() {
  infra.assertive_test_collection_from_data(name, assertive_tests_data(), constructor)
}
