import gleam/list
import gleam/option.{Some}
import gleam/regexp.{type Regexp}
import gleam/string
import infrastructure.{
  type Desugarer,
  type DesugarerTransform,
  type DesugaringError,
  Desugarer,
} as infra
import nodemaps_2_desugarer_transforms as n2t
import vxml.{type Attr, type Line, type VXML, Attr, Line, T, V}
import blame.{type Blame}

// Extract the value token after ##<<:
//   - stops at the first space when not inside a bracket
//   - stops at an unmatched closing bracket (depth would go negative)
//   - stops at end of string
fn do_extract_value(remaining: String, depth: Int, acc: String) -> String {
  case string.pop_grapheme(remaining) {
    Error(_) -> acc
    Ok(#(char, rest)) ->
      case char {
        "(" | "[" | "{" -> do_extract_value(rest, depth + 1, acc <> char)
        ")" | "]" | "}" ->
          case depth {
            0 -> acc
            _ -> do_extract_value(rest, depth - 1, acc <> char)
          }
        " " ->
          case depth {
            0 -> acc
            _ -> do_extract_value(rest, depth, acc <> char)
          }
        _ -> do_extract_value(rest, depth, acc <> char)
      }
  }
}

fn extract_value(s: String) -> String {
  do_extract_value(s, 0, "")
}

// Scan a line's content for in-text handle definitions.
// Processes left-to-right, replacing each valid occurrence of
//   PRECEDING_CHAR + HANDLE_NAME + ##<< + VALUE
// with
//   PRECEDING_CHAR + VALUE
// and collecting handle attrs for the parent V node.
fn process_content(
  remaining: String,
  done: String,
  attrs: List(Attr),
  re: Regexp,
  blame: Blame,
) -> #(String, List(Attr)) {
  case regexp.scan(re, remaining) {
    [] -> #(done <> remaining, attrs)
    [first_match, ..] -> {
      let preceding_char = case first_match.submatches {
        [Some(pc), ..] -> pc
        _ -> ""
      }
      let handle_name = case first_match.submatches {
        [_, Some(hn), ..] -> hn
        _ -> ""
      }
      case handle_name, string.split_once(remaining, first_match.content) {
        "", _ -> #(done <> remaining, attrs)
        _, Error(_) -> #(done <> remaining, attrs)
        _, Ok(#(before, after_marker)) -> {
          let value = extract_value(after_marker)
          let rest = string.drop_start(after_marker, string.length(value))
          let attr_val = infra.normalize_spaces(handle_name <> " " <> value)
          let new_attr = Attr(blame, "handle", attr_val)
          let new_done = done <> before <> preceding_char <> value
          process_content(rest, new_done, [new_attr, ..attrs], re, blame)
        }
      }
    }
  }
}

fn process_line(line: Line, re: Regexp) -> #(Line, List(Attr)) {
  let #(new_content, new_attrs) = process_content(line.content, "", [], re, line.blame)
  #(Line(..line, content: new_content), new_attrs)
}

// State accumulates handle attrs found in T nodes, to be added to the
// closest enclosing V node.
type State =
  List(Attr)

fn t_nodemap(
  vxml: VXML,
  state: State,
  re: Regexp,
) -> Result(#(VXML, State), DesugaringError) {
  let assert T(blame, lines) = vxml
  let #(new_line_attrs, new_lines) =
    list.map_fold(lines, [], fn(acc_attrs, line) {
      let #(new_line, line_attrs) = process_line(line, re)
      #(list.append(line_attrs, acc_attrs), new_line)
    })
  Ok(#(T(blame, new_lines), list.append(new_line_attrs, state)))
}

// Reset the accumulated attrs when entering a V node, so that only
// attrs from *this* V's children are collected for this V.
fn v_before(
  vxml: VXML,
  _state: State,
) -> Result(#(VXML, State), DesugaringError) {
  Ok(#(vxml, []))
}

// After processing a V's children, add the newly-collected handle attrs
// to this V and restore the state to what it was before entering this V.
fn v_after(
  vxml: VXML,
  original_state: State,
  latest_state: State,
) -> Result(#(VXML, State), DesugaringError) {
  let new_handle_attrs = list.reverse(latest_state)
  let assert V(_, _, attrs, _) = vxml
  Ok(#(V(..vxml, attrs: list.append(new_handle_attrs, attrs)), original_state))
}

fn nodemap_factory(re: InnerParam) -> n2t.OneToOneBeforeAndAfterStatefulNodemap(State) {
  n2t.OneToOneBeforeAndAfterStatefulNodemap(
    v_before_transforming_children: v_before,
    v_after_transforming_children: v_after,
    t_nodemap: fn(vxml, state) { t_nodemap(vxml, state, re) },
  )
}

fn transform_factory(inner: InnerParam) -> DesugarerTransform {
  n2t.one_to_one_before_and_after_stateful_nodemap_2_desugarer_transform(
    nodemap_factory(inner),
    [],
  )
}

fn param_to_inner_param(_param: Param) -> Result(InnerParam, DesugaringError) {
  // Matches: (space | '(' | '[')(handleName[#decorator]*)##<<
  // Handle chars:    letters, digits, _, ., :, -, ^
  // Handle end chars: letters, digits, _
  // Decorator chars:  same minus . and ^
  let in_text_def_pattern = "([ \\(\\[])([a-zA-Z0-9_.:\\-\\^]*[a-zA-Z0-9_](?:#[a-zA-Z0-9_:\\-]+)*)##<<"
  let assert Ok(re) = regexp.compile(
    in_text_def_pattern,
    regexp.Options(case_insensitive: False, multi_line: False),
  )
  Ok(re)
}

type Param =
  Nil

type InnerParam =
  Regexp

pub const name = "handles_generate_v_definitions_from_t_definitions"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// Scans every text node (T) for in-text handle
/// definitions of the form
///
///   PRECEDING_CHAR handleName[#decorator...]##<<VALUE
///
/// where PRECEDING_CHAR is a space, '(' or '[';
/// handleName must satisfy the handle-name regex;
/// each #decorator consists of '#' followed by one
/// or more decorator chars; and VALUE is everything
/// after '##<<' up to the first un-bracketed space,
/// end of string, or unmatched closing bracket.
///
/// For each match found, the desugarer:
/// 
///   1. Replaces the matched span with just
///      PRECEDING_CHAR + VALUE in the text.
///   2. Adds a 'handle=handleName VALUE' attribute
///      to the closest ancestor V node of the T node.
///
/// If '##<<' is found but what precedes it does not
/// form a valid handle-name pattern (or has no valid
/// preceding char), that occurrence is left untouched
/// with no error or warning.
///
/// Intended to run before handles_add_ids so that the
/// generated 'handle=' attrs are in the same
/// 'name value' format that handles_add_ids expects.
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
    // Test 1: basic single handle definition (space as preceding char)
    infra.AssertiveTestDataNoParam(
      source: "
        <> root
          <>
            'hello handleBob##<<Bobbba is here'
        ",
      expected: "
        <> root
          handle=handleBob Bobbba
          <>
            'hello Bobbba is here'
        ",
    ),

    // Test 2: handle preceded by '('
    infra.AssertiveTestDataNoParam(
      source: "
        <> root
          <>
            '(handleBob##<<Bobbba rest)'
        ",
      expected: "
        <> root
          handle=handleBob Bobbba
          <>
            '(Bobbba rest)'
        ",
    ),

    // Test 3: handle preceded by '['
    infra.AssertiveTestDataNoParam(
      source: "
        <> root
          <>
            '[handleBob##<<Bobbba rest]'
        ",
      expected: "
        <> root
          handle=handleBob Bobbba
          <>
            '[Bobbba rest]'
        ",
    ),

    // Test 4: no match because '##<<' has no valid preceding space/paren/bracket
    infra.AssertiveTestDataNoParam(
      source: "
        <> root
          <>
            'foo##<<value rest'
        ",
      expected: "
        <> root
          <>
            'foo##<<value rest'
        ",
    ),

    // Test 5: value extraction stops at unmatched closing bracket
    infra.AssertiveTestDataNoParam(
      source: "
        <> root
          <>
            'foo handleBob##<<Value) rest'
        ",
      expected: "
        <> root
          handle=handleBob Value
          <>
            'foo Value) rest'
        ",
    ),

    // Test 6: value with balanced parentheses (space inside parens is not a stop)
    infra.AssertiveTestDataNoParam(
      source: "
        <> root
          <>
            'def handleFn##<<f(x y) more'
        ",
      expected: "
        <> root
          handle=handleFn f(x y)
          <>
            'def f(x y) more'
        ",
    ),

    // Test 7: value extends to end of line (no terminating space)
    infra.AssertiveTestDataNoParam(
      source: "
        <> root
          <>
            'def handleFoo##<<TheValue'
        ",
      expected: "
        <> root
          handle=handleFoo TheValue
          <>
            'def TheValue'
        ",
    ),

    // Test 8: empty value (##<< at end of line)
    infra.AssertiveTestDataNoParam(
      source: "
        <> root
          <>
            'foo handleBob##<<'
        ",
      expected: "
        <> root
          handle=handleBob
          <>
            'foo '
        ",
    ),

    // Test 9: handle with a single decorator
    infra.AssertiveTestDataNoParam(
      source: "
        <> root
          <>
            'see handleBob#page##<<TheValue rest'
        ",
      expected: "
        <> root
          handle=handleBob#page TheValue
          <>
            'see TheValue rest'
        ",
    ),

    // Test 10: handle with multiple decorators
    infra.AssertiveTestDataNoParam(
      source: "
        <> root
          <>
            'see handleBob#page#glossary##<<TheValue rest'
        ",
      expected: "
        <> root
          handle=handleBob#page#glossary TheValue
          <>
            'see TheValue rest'
        ",
    ),

    // Test 11: two definitions on the same line
    infra.AssertiveTestDataNoParam(
      source: "
        <> root
          <>
            'alpha handleA##<<ValA and handleB##<<ValB end'
        ",
      expected: "
        <> root
          handle=handleA ValA
          handle=handleB ValB
          <>
            'alpha ValA and ValB end'
        ",
    ),

    // Test 12: definitions on different lines of the same T node
    infra.AssertiveTestDataNoParam(
      source: "
        <> root
          <>
            'line1 handleA##<<ValA rest'
            'line2 handleB##<<ValB rest'
        ",
      expected: "
        <> root
          handle=handleA ValA
          handle=handleB ValB
          <>
            'line1 ValA rest'
            'line2 ValB rest'
        ",
    ),

    // Test 13: handle in inner V goes to inner V; handle in outer V goes to outer V
    infra.AssertiveTestDataNoParam(
      source: "
        <> root
          <> Outer
            <>
              'outer text handleOuter##<<OuterVal rest'
            <> Inner
              <>
                'inner text handleInner##<<InnerVal rest'
        ",
      expected: "
        <> root
          <> Outer
            handle=handleOuter OuterVal
            <>
              'outer text OuterVal rest'
            <> Inner
              handle=handleInner InnerVal
              <>
                'inner text InnerVal rest'
        ",
    ),

    // Test 14: no ##<< in content at all — no change
    infra.AssertiveTestDataNoParam(
      source: "
        <> root
          <>
            'just ordinary text here'
        ",
      expected: "
        <> root
          <>
            'just ordinary text here'
        ",
    ),

    // Test 15: handle preceded by '(' with nested balanced brackets in value
    infra.AssertiveTestDataNoParam(
      source: "
        <> root
          <>
            '(handleEq##<<f(g(x)) rest'
        ",
      expected: "
        <> root
          handle=handleEq f(g(x))
          <>
            '(f(g(x)) rest'
        ",
    ),

    // Test 16: existing V attrs are preserved, handle attrs prepended
    infra.AssertiveTestDataNoParam(
      source: "
        <> root
          <> Para
            class=intro
            <>
              'hello handleBob##<<Bobbba done'
        ",
      expected: "
        <> root
          <> Para
            handle=handleBob Bobbba
            class=intro
            <>
              'hello Bobbba done'
        ",
    ),

    // Test 17: two separate T nodes in the same V, each contributing a handle
    infra.AssertiveTestDataNoParam(
      source: "
        <> root
          <> Para
            <>
              'first handleA##<<ValA end'
            <>
              'second handleB##<<ValB end'
        ",
      expected: "
        <> root
          <> Para
            handle=handleA ValA
            handle=handleB ValB
            <>
              'first ValA end'
            <>
              'second ValB end'
        ",
    ),

    // Test 18: handle name with dots and colons (valid handle chars)
    infra.AssertiveTestDataNoParam(
      source: "
        <> root
          <>
            'ref section:1.2##<<SectionTitle rest'
        ",
      expected: "
        <> root
          handle=section:1.2 SectionTitle
          <>
            'ref SectionTitle rest'
        ",
    ),

    // Test 19: value with balanced square brackets
    infra.AssertiveTestDataNoParam(
      source: "
        <> root
          <>
            'see handleList##<<[a b] more'
        ",
      expected: "
        <> root
          handle=handleList [a b]
          <>
            'see [a b] more'
        ",
    ),

    // Test 20: ##<< with no preceding valid char at line start — no match
    infra.AssertiveTestDataNoParam(
      source: "
        <> root
          <>
            '##<<value rest'
        ",
      expected: "
        <> root
          <>
            '##<<value rest'
        ",
    ),
  ]
}

pub fn assertive_tests() {
  infra.assertive_test_collection_from_data_no_param(name, assertive_tests_data(), constructor)
}
