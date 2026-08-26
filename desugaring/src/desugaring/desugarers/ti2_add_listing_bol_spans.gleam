import desugaring/authoring
import desugaring/core.{type Desugarer, type DesugarerTransform}
import desugaring/nodemaps_2_transform as n2t
import gleam/list
import on
import vxml.{type Line, type VXML, Attr, T, V}
import vxml/blame as bl

pub const name = "ti2_add_listing_bol_spans"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Adds a beginning-of-line span marker before every line
/// in `pre.listing` elements.
pub fn constructor() -> Desugarer {
  authoring.no_param_desugarer(
    name: name,
    transform: inner_param_to_transform(),
  )
}

const bol_span = V(
  bl.Des([], name, 25),
  // "functions can only be called within other functions..."
  "span",
  [Attr(bl.Des([], name, 28), "class", "listing-bol")],
  [],
)

const empty_line = T(bl.Des([], name, 32), [vxml.Line(bl.Des([], name, 32), "")])

const bol_span_with_texts = [
  empty_line,
  bol_span,
]

fn line_2_t(line: Line) -> VXML {
  T(line.blame, [line])
}

fn nodemap(vxml: VXML) -> VXML {
  case vxml {
    V(_, "pre", attrs, children) -> {
      use <- on.eager_false_true(core.attrs_have_class(attrs, "listing"), vxml)
      let children =
        list.flat_map(children, fn(c) {
          case c {
            T(_, lines) ->
              {
                let ts = list.map(lines, fn(x) { [line_2_t(x)] })
                list.intersperse(ts, bol_span_with_texts)
              }
              |> list.flatten
              |> core.plain_concatenation_in_list
              |> core.delete_singleton_empty_lines_in_list
            _ -> [c]
          }
        })
      V(..vxml, children: [bol_span, ..children])
    }
    _ -> vxml
  }
}

fn inner_param_to_transform() -> DesugarerTransform {
  let nodemap: n2t.OneToOneNoErrorNodemap = nodemap
  nodemap
  |> n2t.one_to_one_no_error_nodemap_2_desugarer_transform
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
fn assertive_tests_data() -> List(core.AssertiveTestDataNoParam) {
  [
    core.AssertiveTestDataNoParam(
      source: "
                <> root
                  <> pre
                    class=listing
                    <>
                      'first line'
                      'second line'
                ",
      expected: "
                <> root
                  <> pre
                    class=listing
                    <> span
                      class=listing-bol
                    <>
                      'first line'
                      ''
                    <> span
                      class=listing-bol
                    <>
                      'second line'
                ",
    ),
    core.AssertiveTestDataNoParam(
      source: "
                <> root
                  <> pre
                    class=listing
                    <>
                      'single line'
                ",
      expected: "
                <> root
                  <> pre
                    class=listing
                    <> span
                      class=listing-bol
                    <>
                      'single line'
                ",
    ),
    core.AssertiveTestDataNoParam(
      source: "
                <> root
                  <> pre
                    class=other
                    <>
                      'should not change'
                ",
      expected: "
                <> root
                  <> pre
                    class=other
                    <>
                      'should not change'
                ",
    ),
  ]
}

pub fn assertive_tests() {
  core.assertive_test_collection_from_data_no_param(
    name,
    assertive_tests_data(),
    constructor,
  )
}
