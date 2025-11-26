import gleam/option.{Some, None}
import gleam/string.{inspect as ins}
import gleam/int
import gleam/list
import infrastructure.{
  type Desugarer,
  type DesugarerTransform,
  type DesugaringError,
  Desugarer,
  DesugaringError,
} as infra
import nodemaps_2_desugarer_transforms as n2t
import vxml.{type VXML, V}
import blame as bl
import on

fn nodemap(
  vxml: VXML,
) -> Result(VXML, DesugaringError) {
  case vxml {
    V(_, "pre", attrs, _) -> {
      use class_attr <- on.ok(
        infra.attrs_unique_key_or_none(attrs, "class"),
      )
      use class_attr <- on.none_some(
        class_attr,
        Ok(vxml),
      )
      let classes = string.split(class_attr.val, " ")
      use #(classes, line_no) <- on.ok(list.try_fold(
        classes,
        #([], None),
        fn (acc, class) {
          case string.starts_with(class, "listing:") || string.starts_with(class, "listing@") {
            False -> Ok(#([class, ..acc.0], acc.1))
            True -> {
              let suffix = string.drop_start(class, 8)
              use line_no <- on.error_ok(
                int.parse(suffix),
                fn(_) { Error(DesugaringError(class_attr.blame, "unable to parse line_no in 'listing:' class: " <> class)) },
              )
              case acc.1 {
                None -> Ok(#(["listing", ..acc.0], Some(line_no)))
                _ -> Error(DesugaringError(class_attr.blame, "found two different 'listing:' in class attr"))
              }
            }
          }
        }
      ))
      let attrs = case line_no {
        None -> attrs
        Some(x) -> infra.attrs_merge_styles(
          attrs,
          desugarer_blame(54),
          "counter-set:listing " <> ins(x - 1),
        )
        |> infra.attrs_set(desugarer_blame(57), "class", string.join(classes |> list.reverse, " "))
      }
      Ok(V(..vxml, attrs: attrs))
    }
    _ -> Ok(vxml)
  }
}

fn nodemap_factory(_inner: InnerParam) -> n2t.OneToOneNodeMap {
  nodemap
}

fn transform_factory(inner: InnerParam) -> DesugarerTransform {
  nodemap_factory(inner)
  |> n2t.one_to_one_nodemap_2_desugarer_transform
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(param)
}

pub const name = "ti2_process_pre_listing_classname"
fn desugarer_blame(line_no: Int) { bl.Des([], name, line_no) }

type Param = Nil
type InnerParam = Param

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// Parses the 'language' attr value of 'pre'
/// elements according to a special format:
///
/// 1. '-listing' suffix is removed and 'listing' is
///    is added as a class to the element instead
/// 
/// 2. '-listing@52' will additionally result in
///    'counter-set:listing 52' being added as a
///    style to the pre
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
      source:   "
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
    infra.AssertiveTestDataNoParam(
      source:   "
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
    infra.AssertiveTestDataNoParam(
      source:   "
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
    infra.AssertiveTestDataNoParam(
      source:   "
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
    infra.AssertiveTestDataNoParam(
      source:   "
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
  infra.assertive_test_collection_from_data_no_param(name, assertive_tests_data(), constructor)
}
