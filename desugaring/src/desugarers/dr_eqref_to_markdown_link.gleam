import gleam/list
import gleam/option
import gleam/regexp.{type Match, Match}
import infrastructure.{
  type Desugarer,
  type DesugarerTransform,
  type DesugaringError,
  Desugarer,
} as infra
import nodemaps_2_desugarer_transforms as n2t
import vxml.{type VXML, Line, T, V}

fn eqref_regexp() -> regexp.Regexp {
  let assert Ok(re) = regexp.from_string("\\\\eqref\\{([^}]+)\\}")
  re
}

fn interleave_with_replacements(
  splits: List(String),
  matches: List(Match),
) -> String {
  case splits, matches {
    [], _ -> ""
    [s], [] -> s
    [s, ..rest_splits], [Match(_, [option.Some(handle)]), ..rest_matches] ->
      s
      <> "[(>>"
      <> handle
      <> ")](>>"
      <> handle
      <> ")"
      <> interleave_with_replacements(rest_splits, rest_matches)
    _, _ -> ""
  }
}

fn replace_eqrefs_in_content(content: String) -> String {
  let re = eqref_regexp()
  let matches = regexp.scan(re, content)
  case matches {
    [] -> content
    _ -> {
      let splits = regexp.split(re, content)
      interleave_with_replacements(splits, matches)
    }
  }
}

fn replace_eqrefs_in_line(line: vxml.Line) -> vxml.Line {
  Line(..line, content: replace_eqrefs_in_content(line.content))
}

fn nodemap(
  vxml: VXML,
  ancestors: List(VXML),
  _: List(VXML),
  _: List(VXML),
  _: List(VXML),
) -> VXML {
  case vxml {
    V(_, _, _, _) -> vxml
    T(blame, lines) -> {
      let inside_math =
        list.any(ancestors, fn(a) {
          let tag = infra.v_get_tag(a)
          tag == "MathBlock" || tag == "Math"
        })
      case inside_math {
        True -> vxml
        False -> T(blame, list.map(lines, replace_eqrefs_in_line))
      }
    }
  }
}

fn nodemap_factory(_: InnerParam) -> n2t.FancyOneToOneNoErrorNodemap {
  nodemap
}

fn transform_factory(inner: InnerParam) -> DesugarerTransform {
  nodemap_factory(inner)
  |> n2t.fancy_one_to_one_no_error_nodemap_2_desugarer_transform
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(param)
}

type Param = Nil
type InnerParam = Nil

pub const name = "dr_eqref_to_markdown_link"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// Replaces `\eqref{XX}` with `[(>>XX)](>>XX)` in
/// text nodes that are not inside a MathBlock or
/// Math ancestor. This turns LaTeX equation
/// cross-references into markdown-style handle links
/// that the handle system can resolve into proper
/// `<a>` elements.
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
  [
    infra.AssertiveTestDataNoParam(
      source: "
                <> Document
                  <>
                    'satisfying \\eqref{eq:foo} and \\eqref{eq:bar} here'
                  <> MathBlock
                    <>
                      '$$\\eqref{eq:foo}$$'
              ",
      expected: "
                <> Document
                  <>
                    'satisfying [(>>eq:foo)](>>eq:foo) and [(>>eq:bar)](>>eq:bar) here'
                  <> MathBlock
                    <>
                      '$$\\eqref{eq:foo}$$'
              ",
    ),
  ]
}

pub fn assertive_tests() {
  infra.assertive_test_collection_from_data_no_param(
    name,
    assertive_tests_data(),
    constructor,
  )
}
