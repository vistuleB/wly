import gleam/list
import gleam/option
import gleam/regexp.{type Regexp}
import gleam/string
import infrastructure.{
  type Desugarer,
  type DesugarerTransform,
  type DesugaringError,
  Desugarer,
} as infra
import nodemaps_2_desugarer_transforms as n2t
import vxml.{Line, T, V}

fn replace_refs_in_content(content: String, re: Regexp) -> String {
  case regexp.scan(re, content) {
    [] -> content
    [first_match, ..] ->
      case first_match.submatches {
        [option.Some(handle_name)] -> {
          let base = case string.split_once(handle_name, "#") {
            Ok(#(before, _)) -> before
            Error(_) -> handle_name
          }
          case string.split_once(content, first_match.content) {
            Error(_) -> content
            Ok(#(before, after)) ->
              before
              <> "\\ref{"
              <> base
              <> "}"
              <> replace_refs_in_content(after, re)
          }
        }
        _ -> content
      }
  }
}

type State =
  Bool

fn nodemap_factory(
  re: Regexp,
) -> n2t.OneToOneNoErrorBeforeAndAfterStatefulNodemap(State) {
  n2t.OneToOneNoErrorBeforeAndAfterStatefulNodemap(
    v_before_transforming_children: fn(vxml, state) {
      let assert V(_, tag, _, _) = vxml
      #(vxml, state || tag == "MathBlock")
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
                content: replace_refs_in_content(line.content, re),
              )
            })
          #(T(blame, new_lines), state)
        }
      }
    },
  )
}

fn transform_factory(re: Regexp) -> DesugarerTransform {
  n2t.one_to_one_no_error_before_and_after_stateful_nodemap_2_desugarer_transform(
    nodemap_factory(re),
    False,
  )
}

fn param_to_inner_param(_param: Param) -> Result(Regexp, DesugaringError) {
  let pattern =
    ">>([a-zA-Z0-9_.:^\\-']+[a-zA-Z0-9_'](?:#[a-zA-Z0-9_:\\-]+)*)"
  let assert Ok(re) =
    regexp.compile(
      pattern,
      regexp.Options(case_insensitive: False, multi_line: False),
    )
  Ok(re)
}

type Param =
  Nil

pub const name = "substitute_bare_eq_refs_in_mathblock"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// Inside T nodes that are descendants of a
/// `MathBlock`, replaces bare handle references of
/// the form `>>handle-name` with the LaTeX cross-
/// reference `\ref{base-name}`, where `base-name`
/// is the handle name stripped of any `#decorator`
/// suffixes.
///
/// This enables referencing a Writerly-labeled
/// equation (defined with `name##<<` bare syntax)
/// from within another MathBlock:
///
///   (>>size-lupanov)&= ...  →  (\ref{size-lupanov})&= ...
///
/// The corresponding `\label{base-name}` is emitted
/// by `math_label_to_tag_handle` alongside each
/// `\tag{}` it produces, so MathJax can resolve
/// `\ref{base-name}` to the equation number.
///
/// Must run after `handles_generate_v_definitions_from_t_definitions`
/// and before `handles_substitute_and_fix_nonlocal_id_links`
/// so that the `>>` token inside MathBlocks is consumed
/// here rather than by the general handle substitution.
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
    // Test 1: basic >>handle-name inside MathBlock → \ref{handle-name}
    infra.AssertiveTestDataNoParam(
      source: "
        <> root
          <> MathBlock
            <>
              '(>>size-lupanov)&= 2^n'
        ",
      expected: "
        <> root
          <> MathBlock
            <>
              '(\\ref{size-lupanov})&= 2^n'
        ",
    ),

    // Test 2: >>handle with colon and hyphen
    infra.AssertiveTestDataNoParam(
      source: "
        <> root
          <> MathBlock
            <>
              '(>>eq:gate-choices) \\leq s^2'
        ",
      expected: "
        <> root
          <> MathBlock
            <>
              '(\\ref{eq:gate-choices}) \\leq s^2'
        ",
    ),

    // Test 3: >>handle-name#decorator → \ref{base-name} (decorator stripped)
    infra.AssertiveTestDataNoParam(
      source: "
        <> root
          <> MathBlock
            <>
              '(>>size-lupanov#page)&= 2^n'
        ",
      expected: "
        <> root
          <> MathBlock
            <>
              '(\\ref{size-lupanov})&= 2^n'
        ",
    ),

    // Test 4: >>handle outside MathBlock → unchanged
    infra.AssertiveTestDataNoParam(
      source: "
        <> root
          <> p
            <>
              'see (>>size-lupanov) for details'
        ",
      expected: "
        <> root
          <> p
            <>
              'see (>>size-lupanov) for details'
        ",
    ),

    // Test 5: multiple >>refs on the same line inside MathBlock
    infra.AssertiveTestDataNoParam(
      source: "
        <> root
          <> MathBlock
            <>
              '(>>eq:first) + (>>eq:second) = total'
        ",
      expected: "
        <> root
          <> MathBlock
            <>
              '(\\ref{eq:first}) + (\\ref{eq:second}) = total'
        ",
    ),

    // Test 6: >>handle on its own line inside MathBlock
    infra.AssertiveTestDataNoParam(
      source: "
        <> root
          <> MathBlock
            <>
              '>>size-lupanov'
        ",
      expected: "
        <> root
          <> MathBlock
            <>
              '\\ref{size-lupanov}'
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
