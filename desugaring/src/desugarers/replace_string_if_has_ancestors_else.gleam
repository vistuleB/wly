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
  ancestors: List(VXML),
  inner: InnerParam,
) -> VXML {
  case vxml {
    T(blame, lines) -> {
      let #(ancestor_tags, if_re, if_to, else_re, else_to) = inner
      
      let has_ancestor = list.any(ancestors, fn(a) { 
        list.contains(ancestor_tags, infra.v_get_tag(a))
      })

      let #(re, to) = case has_ancestor {
        True -> #(if_re, if_to)
        False -> #(else_re, else_to)
      }

      let new_lines =
        list.map(lines, fn(line) {
          Line(..line, content: regexp.replace(re, line.content, to))
        })
      T(blame, new_lines)
    }
    _ -> vxml
  }
}

fn nodemap_factory(inner: InnerParam) -> n2t.FancyOneToOneNoErrorNodemap {
  fn(vxml, ancestors, _s1, _s2, _s3) {
    nodemap(vxml, ancestors, inner)
  }
}

fn transform_factory(inner: InnerParam) -> DesugarerTransform {
  n2t.fancy_one_to_one_no_error_nodemap_2_desugarer_transform(nodemap_factory(inner))
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  let #(ancestors, if_pair, else_pair) = param
  
  case regexp.from_string(if_pair.0), regexp.from_string(else_pair.0) {
    Ok(if_re), Ok(else_re) -> 
        Ok(#(ancestors, if_re, if_pair.1, else_re, else_pair.1))
    Error(_), _ -> 
        Error(DesugaringError(blame.no_blame, "Invalid if-regex: " <> if_pair.0))
    _, Error(_) -> 
        Error(DesugaringError(blame.no_blame, "Invalid else-regex: " <> else_pair.0))
  }
}

type Param = #(List(String), #(String, String), #(String, String))
//             ↖             ↖                ↖
//             ancestors     if version       else version
type InnerParam = #(List(String), regexp.Regexp, String, regexp.Regexp, String)

pub const name = "replace_string_if_has_ancestors_else"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// replaces occurrences of a regex pattern with 
/// another based on whether the text node has any 
/// of the specified ancestors
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
      param: #(["special"], #("``", "“"), #("``", "`")),
      source: "
                <> root
                  <> special
                    <>
                      'Inside special ``backticks``'
                  <> ordinary
                    <>
                      'Outside special ``backticks``'
                ",
      expected: "
                <> root
                  <> special
                    <>
                      'Inside special “backticks“'
                  <> ordinary
                    <>
                      'Outside special `backticks`'
                ",
    ),
  ]
}

pub fn assertive_tests() {
  infra.assertive_test_collection_from_data(name, assertive_tests_data(), constructor)
}
