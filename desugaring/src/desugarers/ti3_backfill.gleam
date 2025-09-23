import gleam/option
import gleam/string.{inspect as ins}
import gleam/int
import gleam/list
import infrastructure.{
  type Desugarer,
  type DesugarerTransform,
  type DesugaringError,
  type TrafficLight,
  DesugaringError,
  Desugarer,
  Continue,
  GoBack,
} as infra
import gleam/regexp.{type Regexp}
import nodemaps_2_desugarer_transforms as n2t
import vxml.{type VXML, V, Attribute}
import blame as bl
import on

const const_blame = bl.Des([], "ti3_backfill", 23)

const stub_sub =
  V(
    const_blame,
    "Sub",
    [Attribute(const_blame, "title", "Lorem Ipsum")],
    [],
  )

const stub_chapter =
  V(
    const_blame,
    "Chapter",
    [Attribute(const_blame, "title", "Lorem Ipsum")],
    [],
  )

fn backfill_elements(
  children: List(VXML),
  stub: VXML,
) -> Result(List(VXML), DesugaringError) {
  let assert V(_, stub_tag, _, _) = stub
  use #(_, children) <- on.ok(
    list.try_fold(
      children,
      #(0, []),
      fn(acc, child) {
        case child {
          V(blame, t, _, _) if t == stub_tag -> {
            use number <- on.lazy_none_some(
              infra.v_value_of_first_attribute_with_key(child, "should-be-number"),
              fn() { Error(DesugaringError(blame, "expecting 'should-be-number' attribute on each " <> stub_tag <> " element")) },
            )
            use number <- on.error_ok(
              int.parse(number),
              fn(_) { Error(DesugaringError(blame, "could not parse should-be-number attribute as integer")) }
            )
            use <- on.lazy_true_false(
              number <= acc.0,
              fn() { Error(DesugaringError(blame, "expecting monotone subchapter numbers (" <> ins(number) <> " <= " <> ins(acc.0) <> ")")) }
            )
            let fill = list.repeat(stub, number - acc.0 - 1)
            let prev = list.append(fill, acc.1)
            Ok(#(number, [child, ..prev]))
          }
          _ -> Ok(#(acc.0, [child, ..acc.1]))
        }
      }
    )
  )
  Ok(children |> list.reverse)
}

fn nodemap(
  node: VXML,
) -> Result(#(VXML, TrafficLight), DesugaringError) {
  case node {
    V(_, "Chapter", _, children) -> {
      use children <- on.ok(backfill_elements(children, stub_sub))
      Ok(#(V(..node, children: children), GoBack))
    }
    V(_, _, _, children) -> {
      use children <- on.ok(backfill_elements(children, stub_chapter))
      Ok(#(V(..node, children: children), Continue))
    }
    _ -> panic as "how could we see anything except 'Chapter' and root, if 'Chapter' orders GoBack?"
  }
}

fn nodemap_factory(_inner: InnerParam) -> n2t.EarlyReturnOneToOneNodeMap {
  nodemap(_)
}

fn transform_factory(inner: InnerParam) -> DesugarerTransform {
  nodemap_factory(inner)
  |> n2t.early_return_one_to_one_nodemap_2_desugarer_transform
}

fn param_to_inner_param(_param: Param) -> Result(InnerParam, DesugaringError) {
  let assert Ok(re_chapter) = regexp.from_string("(\\d\\d)\\/")
  let assert Ok(re_sub) = regexp.from_string("\\d\\d/(\\d\\d)-")
  Ok(#(re_chapter, re_sub))
}

pub const name = "ti3_backfill"

type Param = Nil
type InnerParam = #(Regexp, Regexp)

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// backfills missing numbered Chapter and Sub elements
/// in VXML documents.
///
/// this desugarer processes VXML elements that have a
/// "should-be-number" attribute and fills in any gaps
/// in the numbering sequence by inserting stub elements.
///
/// - for Chapter elements: fills missing Sub elements
/// - for other elements: fills missing Chapter elements
/// - validates numbers are monotonically increasing
/// - uses "Lorem Ipsum" titled stubs as placeholders
pub fn constructor() -> Desugarer {
  Desugarer(
    name: name,
    stringified_param: option.None,
    stringified_outside: option.None,
    transform: case param_to_inner_param(Nil) {
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
                    <> Chapter
                      title=Chapter 1
                      should-be-number=1
                      <> Sub
                        title=Sub 1.1
                        should-be-number=1
                      <> Sub
                        title=Sub 1.3
                        should-be-number=3
                ",
      expected: "
                  <> root
                    <> Chapter
                      title=Chapter 1
                      should-be-number=1
                      <> Sub
                        title=Sub 1.1
                        should-be-number=1
                      <> Sub
                        title=Lorem Ipsum
                      <> Sub
                        title=Sub 1.3
                        should-be-number=3
                ",
    ),
    infra.AssertiveTestDataNoParam(
      source:   "
                  <> root
                    <> Chapter
                      title=Chapter 1
                      should-be-number=1
                    <> Chapter
                      title=Chapter 4
                      should-be-number=4
                ",
      expected: "
                  <> root
                    <> Chapter
                      title=Chapter 1
                      should-be-number=1
                    <> Chapter
                      title=Lorem Ipsum
                    <> Chapter
                      title=Lorem Ipsum
                    <> Chapter
                      title=Chapter 4
                      should-be-number=4
                ",
    ),
    infra.AssertiveTestDataNoParam(
      source:   "
                  <> root
                    <> Chapter
                      title=Chapter 2
                      should-be-number=2
                      <> Sub
                        title=Sub 2.2
                        should-be-number=2
                      <> Sub
                        title=Sub 2.5
                        should-be-number=5
                ",
      expected: "
                  <> root
                    <> Chapter
                      title=Lorem Ipsum
                    <> Chapter
                      title=Chapter 2
                      should-be-number=2
                      <> Sub
                        title=Lorem Ipsum
                      <> Sub
                        title=Sub 2.2
                        should-be-number=2
                      <> Sub
                        title=Lorem Ipsum
                      <> Sub
                        title=Lorem Ipsum
                      <> Sub
                        title=Sub 2.5
                        should-be-number=5
                ",
    ),
  ]
}

pub fn assertive_tests() {
  infra.assertive_test_collection_from_data_no_param(name, assertive_tests_data(), constructor)
}
