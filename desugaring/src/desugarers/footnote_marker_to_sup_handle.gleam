import blame.{type Blame} as bl
import gleam/list
import gleam/option.{Some}
import gleam/regexp.{type Regexp}
import gleam/string.{inspect as ins}
import infrastructure.{
  type Desugarer, type DesugarerTransform, type DesugaringError, Desugarer,
} as infra
import nodemaps_2_desugarer_transforms as n2t
import vxml.{type Line, type VXML, Line, T, V}

fn split_content(
  blame: Blame,
  content: String,
  re: Regexp,
  counter_expr: String,
  target_id: String,
) -> List(VXML) {
  case content {
    "" -> []
    _ -> split_nonempty_content(blame, content, re, counter_expr, target_id)
  }
}

fn split_nonempty_content(
  blame: Blame,
  content: String,
  re: Regexp,
  counter_expr: String,
  target_id: String,
) -> List(VXML) {
  case regexp.scan(re, content) {
    [] -> [T(blame, [Line(blame, content)])]
    [first_match, ..] ->
      case first_match.submatches {
        [Some(handle_name)] ->
          case string.split_once(content, first_match.content) {
            Error(_) -> [T(blame, [Line(blame, content)])]
            Ok(#(before, after)) -> {
              let before_len = string.length(before)
              let match_len = string.length(first_match.content)
              let sup_blame = bl.advance(blame, before_len)
              let after_blame = bl.advance(blame, before_len + match_len)
              let sup_node =
                V(sup_blame, "sup", [], [
                  T(sup_blame, [
                    Line(
                      sup_blame,
                      "["
                        <> handle_name
                        <> "##<<("
                        <> counter_expr
                        <> ")](#"
                        <> target_id
                        <> ")",
                    ),
                  ]),
                ])
              let before_nodes = case before {
                "" -> []
                _ -> [T(blame, [Line(blame, before)])]
              }
              list.flatten([
                before_nodes,
                [sup_node],
                split_content(after_blame, after, re, counter_expr, target_id),
              ])
            }
          }
        _ -> [T(blame, [Line(blame, content)])]
      }
  }
}

fn line_nodemap(
  line: Line,
  re: Regexp,
  counter_expr: String,
  target_id: String,
) -> List(VXML) {
  split_content(line.blame, line.content, re, counter_expr, target_id)
}

fn nodemap(vxml: VXML, inner: InnerParam) -> List(VXML) {
  let #(re, counter_expr, target_id) = inner
  case vxml {
    V(_, _, _, _) -> [vxml]
    T(_, lines) ->
      lines
      |> list.flat_map(line_nodemap(_, re, counter_expr, target_id))
      |> infra.plain_concatenation_in_list
  }
}

fn nodemap_factory(inner: InnerParam) -> n2t.OneToManyNoErrorNodemap {
  nodemap(_, inner)
}

fn transform_factory(inner: InnerParam, outside: List(String)) -> DesugarerTransform {
  nodemap_factory(inner)
  |> n2t.one_to_many_no_error_nodemap_2_desugarer_transform_with_forbidden(outside)
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  let #(counter_expr, target_id) = param
  let pattern = "\\(\\*>>([a-zA-Z0-9_.:^\\-']+(?:#[a-zA-Z0-9_:\\-]+)*)\\)"
  let assert Ok(re) =
    regexp.compile(
      pattern,
      regexp.Options(case_insensitive: False, multi_line: False),
    )
  Ok(#(re, counter_expr, target_id))
}

type Param = #(String, String)
//             ↖       ↖
//             counter  id of the shared anchor
//             increment that every sup produced
//             expression, by this desugarer
//             e.g.       links to, e.g. "footnote"
//             "::++FootnoteCounter"

type InnerParam = #(Regexp, String, String)

pub const name = "footnote_marker_to_sup_handle"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// splits T-node text on occurrences of
/// `(*>>handle_name)` and replaces each with a new
/// `sup` element whose text child reads
///
///   [handle_name##<<(counter_expr)](#target_id)
///
/// i.e. an ordinary markdown-style link, so that the
/// existing `markdown_link_splitting` pipeline
/// fragment (reused as-is, no bespoke link-splitting
/// logic here) turns it into a real `<a>` once a
/// subsequent `substitute_counters` +
/// `handles_generate_v_definitions_from_t_definitions`
/// pass has resolved `counter_expr` and folded the
/// `##<<` marker into a plain value. End result:
/// `<sup><a href="#target_id">(1)</a></sup>`, with
/// `handle="handle_name (1)"` attached to the `sup`.
///
/// `target_id` is the same literal anchor id for every
/// sup this desugarer produces (e.g. "footnote") — it
/// is not derived from handle_name, so it's the
/// caller's job to make sure something on the page
/// (e.g. every `Footnote` block, via
/// `append_attribute__batch`) carries a matching
/// `id=target_id`.
///
/// keeps out of subtrees rooted at tags given by its
/// third argument
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
    // Test 1: basic match, mid-sentence
    infra.AssertiveTestDataWithOutside(
      param: #("::++FootnoteCounter", "footnote"),
      outside: [],
      source: "
        <> root
          <>
            'Fourier transform(*>>fn-fourier-transform) of f'
        ",
      expected: "
        <> root
          <>
            'Fourier transform'
          <> sup
            <>
              '[fn-fourier-transform##<<(::++FootnoteCounter)](#footnote)'
          <>
            ' of f'
        ",
    ),

    // Test 2: no match -> unchanged
    infra.AssertiveTestDataWithOutside(
      param: #("::++FootnoteCounter", "footnote"),
      outside: [],
      source: "
        <> root
          <>
            'nothing to see here'
        ",
      expected: "
        <> root
          <>
            'nothing to see here'
        ",
    ),

    // Test 3: two matches on the same line
    infra.AssertiveTestDataWithOutside(
      param: #("::++FootnoteCounter", "footnote"),
      outside: [],
      source: "
        <> root
          <>
            'a(*>>fn-one) and b(*>>fn-two)'
        ",
      expected: "
        <> root
          <>
            'a'
          <> sup
            <>
              '[fn-one##<<(::++FootnoteCounter)](#footnote)'
          <>
            ' and b'
          <> sup
            <>
              '[fn-two##<<(::++FootnoteCounter)](#footnote)'
        ",
    ),

    // Test 4: match inside a forbidden ancestor -> unchanged
    infra.AssertiveTestDataWithOutside(
      param: #("::++FootnoteCounter", "footnote"),
      outside: ["MathBlock"],
      source: "
        <> root
          <> MathBlock
            <>
              'a(*>>fn-one) b'
        ",
      expected: "
        <> root
          <> MathBlock
            <>
              'a(*>>fn-one) b'
        ",
    ),
  ]
}

pub fn assertive_tests() {
  infra.assertive_test_collection_from_data_with_outside(
    name,
    assertive_tests_data(),
    constructor,
  )
}
