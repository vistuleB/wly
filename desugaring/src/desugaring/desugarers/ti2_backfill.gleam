import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
  type TrafficLight, Continue, DesugaringError, GoBack,
}
import desugaring/nodemaps_2_transform as n2t
import gleam/int
import gleam/io
import gleam/list
import gleam/string.{inspect as ins}
import on
import vxml.{type VXML, Attr, T, V}
import vxml/blame as bl

pub const name = "ti2_backfill"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Backfills gaps in numbered Chapter and Sub sequences
/// with `Lorem Ipsum` placeholder elements.
pub fn constructor() -> Desugarer {
  authoring.no_param_desugarer(
    name: name,
    transform: inner_param_to_transform(),
  )
}

const const_blame = bl.Des([], name, 30)

const stub_sub = V(
  const_blame,
  "Sub",
  [Attr(const_blame, "title", "Lorem Ipsum")],
  [],
)

const stub_chapter = V(
  const_blame,
  "Chapter",
  [Attr(const_blame, "title", "Lorem Ipsum")],
  [],
)

fn backfill_elements(
  children: List(VXML),
  stub: VXML,
) -> Result(List(VXML), DesugaringError) {
  let assert V(_, stub_tag, _, _) = stub
  use #(_, children) <- on.ok(
    list.try_fold(children, #(0, []), fn(acc, child) {
      case child {
        V(blame, t, _, _) if t == stub_tag -> {
          use number <- on.none_some(
            core.v_val_of_first_attr_with_key(child, "should-be-number"),
            fn() {
              Error(DesugaringError(
                blame,
                "expecting 'should-be-number' attr on each "
                  <> stub_tag
                  <> " element",
              ))
            },
          )
          use number <- on.error_ok(int.parse(number), fn(_) {
            Error(DesugaringError(
              blame,
              "could not parse should-be-number attr as integer",
            ))
          })
          use <- on.true_false(number <= acc.0, fn() {
            Error(DesugaringError(
              blame,
              "expecting monotone subchapter numbers ("
                <> ins(number)
                <> " <= "
                <> ins(acc.0)
                <> ")",
            ))
          })
          let fill = list.repeat(stub, number - acc.0 - 1)
          let prev = list.append(fill, acc.1)
          Ok(#(number, [child, ..prev]))
        }
        _ -> Ok(#(acc.0, [child, ..acc.1]))
      }
    }),
  )
  Ok(children |> list.reverse)
}

fn nodemap(node: VXML) -> Result(#(VXML, TrafficLight), DesugaringError) {
  case node {
    V(_, "Chapter", _, children) -> {
      use children <- on.ok(backfill_elements(children, stub_sub))
      Ok(#(V(..node, children: children), GoBack))
    }
    V(_, "Document", _, children) -> {
      use children <- on.ok(backfill_elements(children, stub_chapter))
      Ok(#(V(..node, children: children), Continue))
    }
    V(_, "WriterlyBlankLine", _, _) -> {
      Ok(#(node, Continue))
    }
    V(_, tag, _, _children) -> {
      let msg = "unexpected tag: " <> tag
      panic as msg
    }
    T(_, lines) -> {
      io.println("")
      list.each(lines, fn(line) { io.println(line.content) })
      io.println("")
      let msg = "unexpected text node at top level of Document (printout above)"
      panic as msg
    }
  }
}

fn inner_param_to_transform() -> DesugarerTransform {
  let nodemap: n2t.EarlyReturnOneToOneNodemap = nodemap
  nodemap
  |> n2t.early_return_one_to_one_nodemap_2_desugarer_transform
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
fn assertive_tests_data() -> List(core.AssertiveTestDataNoParam) {
  [
    core.AssertiveTestDataNoParam(
      source: "
                  <> Document
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
                  <> Document
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
    core.AssertiveTestDataNoParam(
      source: "
                  <> Document
                    <> Chapter
                      title=Chapter 1
                      should-be-number=1
                    <> Chapter
                      title=Chapter 4
                      should-be-number=4
                ",
      expected: "
                  <> Document
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
    core.AssertiveTestDataNoParam(
      source: "
                  <> Document
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
                  <> Document
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
  core.assertive_test_collection_from_data_no_param(
    name,
    assertive_tests_data(),
    constructor,
  )
}
