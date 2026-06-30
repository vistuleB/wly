import gleam/list
import gleam/option
import gleam/regexp.{type Regexp}
import gleam/string.{inspect as ins}
import infrastructure.{
  type Desugarer,
  type DesugarerTransform,
  type DesugaringError,
  Desugarer,
} as infra
import nodemaps_2_desugarer_transforms as n2t
import vxml.{Line, T, V}

fn base_handle_name(name: String) -> String {
  case string.split_once(name, "#") {
    Ok(#(before, _)) -> before
    Error(_) -> name
  }
}

fn replace_labels_in_content(
  content: String,
  re: Regexp,
  counter_expr: String,
) -> String {
  case regexp.scan(re, content) {
    [] -> content
    [first_match, ..] ->
      case first_match.submatches {
        [option.Some(keyword), option.Some(name), ..rest] -> {
          let value = case rest {
            [option.Some(v), ..] -> v
            _ -> ""
          }
          case string.split_once(content, first_match.content) {
            Error(_) -> content
            Ok(#(before, after)) -> {
              let label_suffix =
                "\\label{" <> base_handle_name(name) <> "}"
              let replacement = case value {
                "" ->
                  "\\tag{" <> name <> "##<<" <> counter_expr <> "}" <> label_suffix
                existing ->
                  case keyword {
                    "label" ->
                      "\\tag{" <> name <> "##<<" <> existing <> "}" <> label_suffix
                    _ -> first_match.content <> label_suffix
                  }
              }
              before
              <> replacement
              <> replace_labels_in_content(after, re, counter_expr)
            }
          }
        }
        [option.None, option.None, option.None, option.Some(bare_name)] -> {
          case string.split_once(content, first_match.content) {
            Error(_) -> content
            Ok(#(before, after)) ->
              before
              <> "\\tag{"
              <> bare_name
              <> "##<<"
              <> counter_expr
              <> "}\\label{"
              <> base_handle_name(bare_name)
              <> "}"
              <> replace_labels_in_content(after, re, counter_expr)
          }
        }
        _ -> content
      }
  }
}

type State = Bool

fn nodemap_factory(inner: InnerParam) -> n2t.OneToOneNoErrorBeforeAndAfterStatefulNodemap(State) {
  let #(ancestor_tag, counter_expr, re) = inner
  n2t.OneToOneNoErrorBeforeAndAfterStatefulNodemap(
    v_before_transforming_children: fn(vxml, state) {
      let assert V(_, tag, _, _) = vxml
      #(vxml, state || tag == ancestor_tag)
    },
    v_after_transforming_children: fn(vxml, original_state, _latest_state) {
      #(vxml, original_state)
    },
    t_nodemap: fn(vxml, state) {
      case state {
        False -> #(vxml, state)
        True -> {
          let assert T(blame, lines) = vxml
          let new_lines =
            list.map(lines, fn(line) {
              Line(
                ..line,
                content: replace_labels_in_content(line.content, re, counter_expr),
              )
            })
          #(T(blame, new_lines), state)
        }
      }
    },
  )
}

fn transform_factory(inner: InnerParam) -> DesugarerTransform {
  let #(ancestor_tag, _, _) = inner
  n2t.one_to_one_no_error_before_and_after_stateful_nodemap_2_desugarer_transform(
    nodemap_factory(inner),
    ancestor_tag == "",
  )
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  let #(ancestor_tag, counter_expr) = param
  let pattern =
    "\\\\(label|tag)\\{([a-zA-Z0-9_.:^\\-']+(?:#[a-zA-Z0-9_:\\-]+)*)##<<([^}]*)\\}|([a-zA-Z0-9_.:^\\-']+(?:#[a-zA-Z0-9_:\\-]+)*)##<<"
  let assert Ok(re) =
    regexp.compile(
      pattern,
      regexp.Options(case_insensitive: False, multi_line: False),
    )
  Ok(#(ancestor_tag, counter_expr, re))
}

type Param =
  #(String, String)
//  ↖         ↖
//  ancestor  counter
//  tag       expression

type InnerParam =
  #(String, String, Regexp)
//  ↖         ↖       ↖
//  ancestor  counter compiled
//  tag       expr    regex

pub const name = "math_label_to_tag_handle"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// Inside T nodes that are descendants of
/// `ancestor_tag` (or all T nodes when
/// `ancestor_tag` is `""`), processes occurrences
/// of `\label{name##<<…}`, `\tag{name##<<…}`, and
/// bare `name##<<` (without any LaTeX wrapper):
///
///   \label{name##<<}   → \tag{name##<<counter_expr}
///   \tag{name##<<}     → \tag{name##<<counter_expr}
///   \label{name##<<v}  → \tag{name##<<v}  (keep value)
///   \tag{name##<<v}    → unchanged
///   name##<<           → \tag{name##<<counter_expr}
///
/// `\label{name}` (without `##<<`) is not matched
/// and is left untouched (treated as a vanilla
/// MathJax label, not a Writerly handle).
///
/// Must run before `substitute_counters` so that
/// counter expressions in the generated
/// `\tag{name##<<counter_expr}` get substituted.
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
    // Test 1: \label{name##<<} inside MathBlock → fills counter + adds \label
    infra.AssertiveTestData(
      param: #("MathBlock", "::øøSectionCounter.::++EquationCounter"),
      source: "
        <> root
          <> MathBlock
            <>
              'a = b \\label{eq:lebesgue##<<}'
        ",
      expected: "
        <> root
          <> MathBlock
            <>
              'a = b \\tag{eq:lebesgue##<<::øøSectionCounter.::++EquationCounter}\\label{eq:lebesgue}'
        ",
    ),

    // Test 2: \label{name##<<} outside ancestor tag → no change
    infra.AssertiveTestData(
      param: #("MathBlock", "::øøSectionCounter.::++EquationCounter"),
      source: "
        <> root
          <>
            'a = b \\label{eq:lebesgue##<<}'
        ",
      expected: "
        <> root
          <>
            'a = b \\label{eq:lebesgue##<<}'
        ",
    ),

    // Test 3: multiple \label{name##<<} on separate lines
    infra.AssertiveTestData(
      param: #("MathBlock", "::øøSectionCounter.::++EquationCounter"),
      source: "
        <> root
          <> MathBlock
            <>
              'a = b \\label{eq:first##<<}'
              'c = d \\label{eq:second##<<}'
        ",
      expected: "
        <> root
          <> MathBlock
            <>
              'a = b \\tag{eq:first##<<::øøSectionCounter.::++EquationCounter}\\label{eq:first}'
              'c = d \\tag{eq:second##<<::øøSectionCounter.::++EquationCounter}\\label{eq:second}'
        ",
    ),

    // Test 4: label name with colons and hyphens
    infra.AssertiveTestData(
      param: #("MathBlock", "::øøSectionCounter.::++EquationCounter"),
      source: "
        <> root
          <> MathBlock
            <>
              'x = y \\label{eq:sec-1:item##<<}'
        ",
      expected: "
        <> root
          <> MathBlock
            <>
              'x = y \\tag{eq:sec-1:item##<<::øøSectionCounter.::++EquationCounter}\\label{eq:sec-1:item}'
        ",
    ),

    // Test 5: \tag{name##<<value} with value already set → adds \label
    infra.AssertiveTestData(
      param: #("MathBlock", "::øøSectionCounter.::++EquationCounter"),
      source: "
        <> root
          <> MathBlock
            <>
              'a = b \\tag{eq:explicit##<<A}'
        ",
      expected: "
        <> root
          <> MathBlock
            <>
              'a = b \\tag{eq:explicit##<<A}\\label{eq:explicit}'
        ",
    ),

    // Test 6: empty ancestor_tag applies to all T nodes
    infra.AssertiveTestData(
      param: #("", "::++EqCounter"),
      source: "
        <> root
          <>
            'a = b \\label{eq:lebesgue##<<}'
        ",
      expected: "
        <> root
          <>
            'a = b \\tag{eq:lebesgue##<<::++EqCounter}\\label{eq:lebesgue}'
        ",
    ),

    // Test 7: two \label{##<<} on the same line
    infra.AssertiveTestData(
      param: #("MathBlock", "::++EqCounter"),
      source: "
        <> root
          <> MathBlock
            <>
              '& a = b \\label{eq:line1##<<} & c = d \\label{eq:line2##<<}'
        ",
      expected: "
        <> root
          <> MathBlock
            <>
              '& a = b \\tag{eq:line1##<<::++EqCounter}\\label{eq:line1} & c = d \\tag{eq:line2##<<::++EqCounter}\\label{eq:line2}'
        ",
    ),

    // Test 8: \tag{name##<<} (tag form, empty value) → fills counter + adds \label
    infra.AssertiveTestData(
      param: #("MathBlock", "::++EqCounter"),
      source: "
        <> root
          <> MathBlock
            <>
              'a = b \\tag{eq:foo##<<}'
        ",
      expected: "
        <> root
          <> MathBlock
            <>
              'a = b \\tag{eq:foo##<<::++EqCounter}\\label{eq:foo}'
        ",
    ),

    // Test 9: \label{name##<<value} → changes \label to \tag, preserves value, adds \label
    infra.AssertiveTestData(
      param: #("MathBlock", "::++EqCounter"),
      source: "
        <> root
          <> MathBlock
            <>
              'a = b \\label{eq:foo##<<A}'
        ",
      expected: "
        <> root
          <> MathBlock
            <>
              'a = b \\tag{eq:foo##<<A}\\label{eq:foo}'
        ",
    ),

    // Test 10: \label{name} without ##<< → not matched, left unchanged
    infra.AssertiveTestData(
      param: #("MathBlock", "::++EqCounter"),
      source: "
        <> root
          <> MathBlock
            <>
              'a = b \\label{eq:foo}'
        ",
      expected: "
        <> root
          <> MathBlock
            <>
              'a = b \\label{eq:foo}'
        ",
    ),

    // Test 11: bare name##<< inside MathBlock → fills counter + adds \label
    infra.AssertiveTestData(
      param: #("MathBlock", "::++EqCounter"),
      source: "
        <> root
          <> MathBlock
            <>
              'a = b eq:lebesgue##<<'
        ",
      expected: "
        <> root
          <> MathBlock
            <>
              'a = b \\tag{eq:lebesgue##<<::++EqCounter}\\label{eq:lebesgue}'
        ",
    ),

    // Test 12: bare name##<< outside ancestor tag → no change
    infra.AssertiveTestData(
      param: #("MathBlock", "::++EqCounter"),
      source: "
        <> root
          <>
            'a = b eq:lebesgue##<<'
        ",
      expected: "
        <> root
          <>
            'a = b eq:lebesgue##<<'
        ",
    ),

    // Test 13: bare name##<< with empty ancestor_tag applies to all T nodes
    infra.AssertiveTestData(
      param: #("", "::++EqCounter"),
      source: "
        <> root
          <>
            'a = b eq:lebesgue##<<'
        ",
      expected: "
        <> root
          <>
            'a = b \\tag{eq:lebesgue##<<::++EqCounter}\\label{eq:lebesgue}'
        ",
    ),

    // Test 15: bare name#decorator##<< inside MathBlock → fills counter, \label uses base name
    infra.AssertiveTestData(
      param: #("MathBlock", "::++EqCounter"),
      source: "
        <> root
          <> MathBlock
            <>
              'a + b = c eq:lebesgue#page##<<'
        ",
      expected: "
        <> root
          <> MathBlock
            <>
              'a + b = c \\tag{eq:lebesgue#page##<<::++EqCounter}\\label{eq:lebesgue}'
        ",
    ),

    // Test 16: \label{name#decorator##<<} → converts to \tag, \label uses base name
    infra.AssertiveTestData(
      param: #("MathBlock", "::++EqCounter"),
      source: "
        <> root
          <> MathBlock
            <>
              'a = b \\label{eq:foo#page##<<}'
        ",
      expected: "
        <> root
          <> MathBlock
            <>
              'a = b \\tag{eq:foo#page##<<::++EqCounter}\\label{eq:foo}'
        ",
    ),

    // Test 17: multiple decorators on bare form → \label uses base name
    infra.AssertiveTestData(
      param: #("MathBlock", "::++EqCounter"),
      source: "
        <> root
          <> MathBlock
            <>
              'x = y eq:thm#page#glossary##<<'
        ",
      expected: "
        <> root
          <> MathBlock
            <>
              'x = y \\tag{eq:thm#page#glossary##<<::++EqCounter}\\label{eq:thm}'
        ",
    ),

    // Test 18: \tag{name#decorator##<<} with existing value → adds \label with base name
    infra.AssertiveTestData(
      param: #("MathBlock", "::++EqCounter"),
      source: "
        <> root
          <> MathBlock
            <>
              'a = b \\tag{eq:foo#page##<<A}'
        ",
      expected: "
        <> root
          <> MathBlock
            <>
              'a = b \\tag{eq:foo#page##<<A}\\label{eq:foo}'
        ",
    ),

    // Test 19: \label{name#decorator##<<value} → changes to \tag, \label uses base name
    infra.AssertiveTestData(
      param: #("MathBlock", "::++EqCounter"),
      source: "
        <> root
          <> MathBlock
            <>
              'a = b \\label{eq:foo#page##<<A}'
        ",
      expected: "
        <> root
          <> MathBlock
            <>
              'a = b \\tag{eq:foo#page##<<A}\\label{eq:foo}'
        ",
    ),

    // Test 20: bare name#decorator##<< outside MathBlock → no change
    infra.AssertiveTestData(
      param: #("MathBlock", "::++EqCounter"),
      source: "
        <> root
          <>
            'a + b = c eq:lebesgue#page##<<'
        ",
      expected: "
        <> root
          <>
            'a + b = c eq:lebesgue#page##<<'
        ",
    ),

    // Test 21: bare name with prime char (e.g. left-reduction-w')
    infra.AssertiveTestData(
      param: #("MathBlock", "::++EqCounter"),
      source: "
        <> root
          <> MathBlock
            <>
              'a = b left-reduction-w'##<<'
        ",
      expected: "
        <> root
          <> MathBlock
            <>
              'a = b \\tag{left-reduction-w'##<<::++EqCounter}\\label{left-reduction-w'}'
        ",
    ),

    // Test 22: \\label with prime in handle name
    infra.AssertiveTestData(
      param: #("MathBlock", "::++EqCounter"),
      source: "
        <> root
          <> MathBlock
            <>
              'a = b \\label{left-reduction-w'##<<}'
        ",
      expected: "
        <> root
          <> MathBlock
            <>
              'a = b \\tag{left-reduction-w'##<<::++EqCounter}\\label{left-reduction-w'}'
        ",
    ),

    // Test 14: bare name##<< alongside \label{...} on separate lines
    infra.AssertiveTestData(
      param: #("MathBlock", "::++EqCounter"),
      source: "
        <> root
          <> MathBlock
            <>
              'a = b \\label{eq:first##<<}'
              'c = d eq:second##<<'
        ",
      expected: "
        <> root
          <> MathBlock
            <>
              'a = b \\tag{eq:first##<<::++EqCounter}\\label{eq:first}'
              'c = d \\tag{eq:second##<<::++EqCounter}\\label{eq:second}'
        ",
    ),
  ]
}

pub fn assertive_tests() {
  infra.assertive_test_collection_from_data(name, assertive_tests_data(), constructor)
}
