import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError, DesugaringError,
}
import desugaring/nodemaps_2_transform as n2t
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/string.{inspect as ins}
import on
import vxml.{type VXML, V}
import vxml/blame as bl

pub const name = "ti2_process_pre_listing_classname"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Converts listing suffixes in pre language attrs into
/// listing classes and optional counter styles.
pub fn constructor() -> Desugarer {
  authoring.no_param_desugarer(
    name: name,
    transform: inner_param_to_transform(),
  )
}

fn nodemap(vxml: VXML) -> Result(VXML, DesugaringError) {
  case vxml {
    V(_, "pre", attrs, _) -> {
      use class_attr <- on.ok(core.attrs_unique_key_or_none(attrs, "class"))
      use class_attr <- on.none_some(class_attr, fn() { Ok(vxml) })
      let classes = string.split(class_attr.val, " ")
      use #(classes, line_no) <- on.ok(
        list.try_fold(classes, #([], None), fn(acc, class) {
          case
            string.starts_with(class, "listing:")
            || string.starts_with(class, "listing@")
          {
            False -> Ok(#([class, ..acc.0], acc.1))
            True -> {
              let suffix = string.drop_start(class, 8)
              use line_no <- on.error_ok(int.parse(suffix), fn(_) {
                Error(DesugaringError(
                  class_attr.blame,
                  "unable to parse line_no in 'listing:' class: " <> class,
                ))
              })
              case acc.1 {
                None -> Ok(#(["listing", ..acc.0], Some(line_no)))
                _ ->
                  Error(DesugaringError(
                    class_attr.blame,
                    "found two different 'listing:' in class attr",
                  ))
              }
            }
          }
        }),
      )
      let attrs = case line_no {
        None -> attrs
        Some(x) ->
          core.attrs_merge_styles(
            attrs,
            desugarer_blame(67),
            "counter-set:listing " <> ins(x - 1),
          )
          |> core.attrs_set(
            desugarer_blame(71),
            "class",
            string.join(classes |> list.reverse, " "),
          )
      }
      Ok(V(..vxml, attrs: attrs))
    }
    _ -> Ok(vxml)
  }
}

fn nodemap_factory() -> n2t.OneToOneNodemap {
  nodemap
}

fn inner_param_to_transform() -> DesugarerTransform {
  nodemap_factory()
  |> n2t.one_to_one_nodemap_2_desugarer_transform
}

fn desugarer_blame(line_no: Int) {
  bl.Des([], name, line_no)
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
                      language=orange-comments
                      <>
                        'some code here'
                ",
      expected: "
                  <> root
                    <> pre
                      language=orange-comments
                      <>
                        'some code here'
                ",
    ),
    core.AssertiveTestDataNoParam(
      source: "
                  <> root
                    <> pre
                      language=python
                      class=listing
                      <>
                        'def hello():'
                        '    print('world')'
                ",
      expected: "
                  <> root
                    <> pre
                      language=python
                      class=listing
                      <>
                        'def hello():'
                        '    print('world')'
                ",
    ),
    core.AssertiveTestDataNoParam(
      source: "
                  <> root
                    <> pre
                      language=javascript
                      class=bob listing@10
                      <>
                        'console.log('test');'
                ",
      expected: "
                  <> root
                    <> pre
                      language=javascript
                      class=bob listing
                      style=counter-set:listing 9
                      <>
                        'console.log('test');'
                ",
    ),
    core.AssertiveTestDataNoParam(
      source: "
                  <> root
                    <> pre
                      class=listing:3
                      <>
                        'line one'
                        'line two'
                ",
      expected: "
                  <> root
                    <> pre
                      class=listing
                      style=counter-set:listing 2
                      <>
                        'line one'
                        'line two'
                ",
    ),
    core.AssertiveTestDataNoParam(
      source: "
                  <> root
                    <> pre
                      <>
                        'plain code block'
                ",
      expected: "
                  <> root
                    <> pre
                      <>
                        'plain code block'
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
