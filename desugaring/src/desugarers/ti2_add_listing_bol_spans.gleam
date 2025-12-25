import gleam/list
import gleam/option.{None}
import infrastructure.{type Desugarer, Desugarer, type DesugarerTransform, type DesugaringError} as infra
import nodemaps_2_desugarer_transforms as n2t
import vxml.{type Line, type VXML, Attr, T, V}
import blame as bl
import on

const bol_span =
  V(
    bl.Des([], name, 11), // "functions can only be called within other functions..."
    "span",
    [Attr(bl.Des([], name, 13), "class", "listing-bol")],
    [],
  )

const empty_line =
  T(
    bl.Des([], name, 19),
    [vxml.Line(bl.Des([], name, 20), "")],
  )

const bol_span_with_texts = [
  empty_line,
  bol_span,
]

fn line_2_t(line: Line) -> VXML {
  T(line.blame, [line])
}

fn nodemap(
  vxml: VXML,
) -> VXML {
  case vxml {
    V(_, "pre", attrs, children) -> {
      use <- on.eager_false_true(
        infra.attrs_have_class(attrs, "listing"),
        vxml,
      )
      let children = list.flat_map(
        children,
        fn(c) {
          case c {
            T(_, lines) -> {
              let ts = list.map(lines, fn(x) { [line_2_t(x)] })
              list.intersperse(ts, bol_span_with_texts)
            }
            |> list.flatten
            |> infra.plain_concatenation_in_list
            |> infra.delete_singleton_empty_lines_in_list
            _ -> [c]
          }
        }
      )
      V(..vxml, children: [bol_span, ..children])
    }
    _ -> vxml
  }
}

fn nodemap_factory(_: InnerParam) -> n2t.OneToOneNoErrorNodeMap {
  nodemap(_)
}

fn transform_factory(inner: InnerParam) -> DesugarerTransform {
  nodemap_factory(inner)
  |> n2t.one_to_one_no_error_nodemap_2_desugarer_transform
}

fn param_to_inner_param(_param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(Nil)
}

pub const name = "ti2_add_listing_bol_spans"

type Param = Nil
type InnerParam = Nil

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// Adds beginning-of-line (BOL) span markers to pre
/// elements with class="listing".
/// 
/// Transforms each text line in listing pre elements by
/// adding span elements with class="listing-bol" at the
/// beginning of each line for proper formatting.
pub fn constructor() -> Desugarer {
  Desugarer(
    name,
    None,
    None,
    case param_to_inner_param(Nil) {
      Error(e) -> fn(_) { Error(e) }
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
      source:   "
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
    infra.AssertiveTestDataNoParam(
      source:   "
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
    infra.AssertiveTestDataNoParam(
      source:   "
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
  infra.assertive_test_collection_from_data_no_param(name, assertive_tests_data(), constructor)
}
