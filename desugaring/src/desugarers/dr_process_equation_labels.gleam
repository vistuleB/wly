import gleam/int
import gleam/list
import gleam/option.{Some}
import gleam/regexp.{Match}
import gleam/string
import infrastructure.{
  type Desugarer,
  type DesugarerTransform,
  type DesugaringError,
  Desugarer,
} as infra
import nodemaps_2_desugarer_transforms as n2t
import vxml.{type VXML, Attr, Line, T, V}
import blame as bl

fn label_regexp() -> regexp.Regexp {
  let assert Ok(re) = regexp.from_string("\\\\label\\{([^}]+)\\}")
  re
}

fn extract_first_label(content: String) -> Result(String, Nil) {
  case regexp.scan(label_regexp(), content) {
    [Match(_, [Some(label)]), ..] -> Ok(label)
    _ -> Error(Nil)
  }
}

fn replace_label_in_line_content(content: String, label: String, tag_val: String) -> String {
  string.replace(content, "\\label{" <> label <> "}", "\\tag{" <> tag_val <> "}")
}

fn replace_label_in_lines(
  lines: List(vxml.Line),
  label: String,
  tag_val: String,
) -> List(vxml.Line) {
  list.map(lines, fn(line) {
    Line(..line, content: replace_label_in_line_content(line.content, label, tag_val))
  })
}

fn find_first_label_in_children(children: List(VXML)) -> Result(String, Nil) {
  list.find_map(children, fn(child) {
    case child {
      T(_, lines) ->
        list.find_map(lines, fn(line) { extract_first_label(line.content) })
      V(_, _, _, _) -> Error(Nil)
    }
  })
}

fn replace_label_in_children(
  children: List(VXML),
  label: String,
  tag_val: String,
) -> List(VXML) {
  list.map(children, fn(child) {
    case child {
      T(blame, lines) -> T(blame, replace_label_in_lines(lines, label, tag_val))
      V(_, _, _, _) -> child
    }
  })
}

fn process_mathblock(vxml: VXML, state: State) -> #(VXML, State) {
  let assert V(blame, "MathBlock", attrs, children) = vxml
  case find_first_label_in_children(children) {
    Error(_) -> #(vxml, state)
    Ok(label) -> {
      let new_eq = state.equation + 1
      let tag_val =
        int.to_string(state.chapter) <> "." <> int.to_string(new_eq)
      let handle_attr = Attr(desugarer_blame(64), "handle", label <> " " <> tag_val)
      let new_attrs = [handle_attr, ..attrs]
      let new_children = replace_label_in_children(children, label, tag_val)
      let new_vxml = V(blame, "MathBlock", new_attrs, new_children)
      let new_state = State(..state, equation: new_eq)
      #(new_vxml, new_state)
    }
  }
}

fn v_before(vxml: VXML, state: State) -> #(VXML, State) {
  case vxml {
    V(_, "Chapter", _, _) ->
      #(vxml, State(chapter: state.chapter + 1, equation: 0))
    V(_, "MathBlock", _, _) ->
      process_mathblock(vxml, state)
    _ -> #(vxml, state)
  }
}

fn v_after(vxml: VXML, _original: State, latest: State) -> #(VXML, State) {
  #(vxml, latest)
}

fn t_nodemap(vxml: VXML, state: State) -> #(VXML, State) {
  #(vxml, state)
}

fn nodemap_factory() -> n2t.OneToOneNoErrorBeforeAndAfterStatefulNodemap(State) {
  n2t.OneToOneNoErrorBeforeAndAfterStatefulNodemap(
    v_before_transforming_children: v_before,
    v_after_transforming_children: v_after,
    t_nodemap: t_nodemap,
  )
}

fn transform_factory(_: InnerParam) -> DesugarerTransform {
  n2t.one_to_one_no_error_before_and_after_stateful_nodemap_2_desugarer_transform(
    nodemap_factory(),
    State(chapter: 0, equation: 0),
  )
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(param)
}

type State {
  State(chapter: Int, equation: Int)
}

type Param = Nil
type InnerParam = Nil

pub const name = "dr_process_equation_labels"

fn desugarer_blame(line_no: Int) {
  bl.Des([], name, line_no)
}

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// Scans MathBlock nodes for `\label{XX}` in their
/// text content. For each MathBlock with a label:
///   - adds `handle=XX chap.eq` attr to the MathBlock
///   - replaces `\label{XX}` with `\tag{chap.eq}` in
///     the text (using chapter.equation numbering)
/// Equation counters reset at each Chapter boundary.
/// Only the first \label per MathBlock is handled
/// (v1.0).
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
                  <> Chapter
                    <>
                      <> MathBlock
                        <>
                          '$$\\begin{align}\\label{eq:foo} x = 1 \\end{align}$$'
                      <> MathBlock
                        <>
                          '$$\\begin{align}\\label{eq:bar} y = 2 \\end{align}$$'
                  <> Chapter
                    <>
                      <> MathBlock
                        <>
                          '$$\\begin{align}\\label{eq:baz} z = 3 \\end{align}$$'
              ",
      expected: "
                <> Document
                  <> Chapter
                    <>
                      <> MathBlock
                        handle=eq:foo 1.1
                        <>
                          '$$\\begin{align}\\tag{1.1} x = 1 \\end{align}$$'
                      <> MathBlock
                        handle=eq:bar 1.2
                        <>
                          '$$\\begin{align}\\tag{1.2} y = 2 \\end{align}$$'
                  <> Chapter
                    <>
                      <> MathBlock
                        handle=eq:baz 2.1
                        <>
                          '$$\\begin{align}\\tag{2.1} z = 3 \\end{align}$$'
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
