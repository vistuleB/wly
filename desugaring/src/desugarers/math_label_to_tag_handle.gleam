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

fn replace_labels_in_content(
  content: String,
  re: Regexp,
  counter_expr: String,
) -> String {
  case regexp.scan(re, content) {
    [] -> content
    [first_match, ..] -> {
      let label_name = case first_match.submatches {
        [option.Some(name), ..] -> name
        _ -> ""
      }
      case string.split_once(content, first_match.content) {
        Error(_) -> content
        Ok(#(before, after)) -> {
          let replacement =
            "\\tag{" <> label_name <> "##<<" <> counter_expr <> "}"
          before
          <> replacement
          <> replace_labels_in_content(after, re, counter_expr)
        }
      }
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
  let pattern = "\\\\label\\{([a-zA-Z0-9_.:^\\-]+)\\}"
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
/// `ancestor_tag`, replaces every occurrence of
///
///   \label{name}
///
/// with
///
///   \tag{name##<<counter_expression}
///
/// The `##<<counter_expression` part is then
/// processed by
/// `handles_generate_v_definitions_from_t_definitions`
/// which records `handle=name <value>` on the
/// closest enclosing V node.
///
/// Allows authors to write the natural LaTeX-style
/// `\label{eq:foo}` instead of the verbose
/// `\tag{eq:foo##<<::øøSec.::++Eq}` form.
///
/// Must run after `create_mathblock_elements`
/// (so the ancestor MathBlock nodes exist) and
/// before
/// `handles_generate_v_definitions_from_t_definitions`.
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
    // Test 1: basic \label replacement inside MathBlock
    infra.AssertiveTestData(
      param: #("MathBlock", "::øøSectionCounter.::++EquationCounter"),
      source: "
        <> root
          <> MathBlock
            <>
              'a = b \\label{eq:lebesgue}'
        ",
      expected: "
        <> root
          <> MathBlock
            <>
              'a = b \\tag{eq:lebesgue##<<::øøSectionCounter.::++EquationCounter}'
        ",
    ),

    // Test 2: no change when not inside the ancestor tag
    infra.AssertiveTestData(
      param: #("MathBlock", "::øøSectionCounter.::++EquationCounter"),
      source: "
        <> root
          <>
            'a = b \\label{eq:lebesgue}'
        ",
      expected: "
        <> root
          <>
            'a = b \\label{eq:lebesgue}'
        ",
    ),

    // Test 3: multiple labels on separate lines in one MathBlock
    infra.AssertiveTestData(
      param: #("MathBlock", "::øøSectionCounter.::++EquationCounter"),
      source: "
        <> root
          <> MathBlock
            <>
              'a = b \\label{eq:first}'
              'c = d \\label{eq:second}'
        ",
      expected: "
        <> root
          <> MathBlock
            <>
              'a = b \\tag{eq:first##<<::øøSectionCounter.::++EquationCounter}'
              'c = d \\tag{eq:second##<<::øøSectionCounter.::++EquationCounter}'
        ",
    ),

    // Test 4: label name with colons and hyphens
    infra.AssertiveTestData(
      param: #("MathBlock", "::øøSectionCounter.::++EquationCounter"),
      source: "
        <> root
          <> MathBlock
            <>
              'x = y \\label{eq:sec-1:item}'
        ",
      expected: "
        <> root
          <> MathBlock
            <>
              'x = y \\tag{eq:sec-1:item##<<::øøSectionCounter.::++EquationCounter}'
        ",
    ),

    // Test 5: no \label present — no change inside MathBlock either
    infra.AssertiveTestData(
      param: #("MathBlock", "::øøSectionCounter.::++EquationCounter"),
      source: "
        <> root
          <> MathBlock
            <>
              'a = b \\tag{eq:explicit##<<(A)}'
        ",
      expected: "
        <> root
          <> MathBlock
            <>
              'a = b \\tag{eq:explicit##<<(A)}'
        ",
    ),

    // Test 6: empty ancestor_tag ("") applies to all T nodes regardless of ancestors
    infra.AssertiveTestData(
      param: #("", "::++EqCounter"),
      source: "
        <> root
          <>
            'a = b \\label{eq:lebesgue}'
        ",
      expected: "
        <> root
          <>
            'a = b \\tag{eq:lebesgue##<<::++EqCounter}'
        ",
    ),

    // Test 7: two labels on the same line
    infra.AssertiveTestData(
      param: #("MathBlock", "::++EqCounter"),
      source: "
        <> root
          <> MathBlock
            <>
              '& a = b \\label{eq:line1} & c = d \\label{eq:line2}'
        ",
      expected: "
        <> root
          <> MathBlock
            <>
              '& a = b \\tag{eq:line1##<<::++EqCounter} & c = d \\tag{eq:line2##<<::++EqCounter}'
        ",
    ),
  ]
}

pub fn assertive_tests() {
  infra.assertive_test_collection_from_data(name, assertive_tests_data(), constructor)
}
