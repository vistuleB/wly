import gleam/option.{Some, None}
import gleam/string.{inspect as ins}
import gleam/int
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
    V(_, "CodeBlock", attrs, _) | V(_, "WriterlyCodeBlock", attrs, _) -> {
      use language <- on.lazy_none_some(
        infra.v_first_attribute_with_key(vxml, "language"),
        fn() { Ok(V(..vxml, tag: "pre")) },
      )

      use #(amended_language, listing, line_no) <- on.ok(
        case string.split_once(language.value, "listing") {
          Ok(#(before, after)) -> {
            let listing = language.blame |> bl.advance(string.length(before))

            let language = case string.ends_with(before, "-") {
              True -> string.drop_end(before, 1) |> string.trim
              False -> before |> string.trim
            }

            use line_no <- on.ok(
              case string.split_once(after, "@") {
                Ok(#("", after)) -> {
                  case int.parse(after) {
                    Ok(line_no) -> Ok(Some(ins(line_no - 1)))
                    _ -> Error(DesugaringError(vxml.blame, "cannot parse '@' line number as integer: " <> after))
                  }
                }
                _ -> Ok(None)
              }
            )

            Ok(#(Some(language), Some(listing), line_no))
          }
          
          _ -> Ok(#(None, None, None))
        }
      )

      let attrs = case listing {
        Some(blame) -> {
          let attrs = infra.attributes_append_classes(attrs, blame, "listing")
          case line_no {
            Some(x) -> infra.attributes_set_styles(attrs, blame, "counter-set:listing " <> x)
            None -> attrs
          }
        }
        None -> attrs
      }

      let attrs = case amended_language {
        Some("") ->
          infra.attributes_delete(attrs, "language")          
        Some(val) ->
          infra.attributes_set(attrs, language.blame, "language", val)
        None -> attrs
      }

      V(
        ..vxml,
        tag: "pre",
        attributes: attrs,
      )
      |> Ok
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

pub const name = "ti3_code_block_to_pre"

type Param = Nil
type InnerParam = Param

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// Converts CodeBlock and WriterlyCodeBlock elements to
/// pre elements with proper language and listing support.
/// 
/// Handles special "listing" directive in language
/// attributes to add listing class and line numbering.
/// Supports syntax like "python-listing@5" for language
/// with listing starting at line 5.
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
                    <> CodeBlock
                      language=orange-comments
                      <>
                        \"some code here\"
                ",
      expected: "
                  <> root
                    <> pre
                      language=orange-comments
                      <>
                        \"some code here\"
                ",
    ),
    infra.AssertiveTestDataNoParam(
      source:   "
                  <> root
                    <> WriterlyCodeBlock
                      language=python-listing
                      <>
                        \"def hello():\"
                        \"    print('world')\"
                ",
      expected: "
                  <> root
                    <> pre
                      language=python
                      class=listing
                      <>
                        \"def hello():\"
                        \"    print('world')\"
                ",
    ),
    infra.AssertiveTestDataNoParam(
      source:   "
                  <> root
                    <> CodeBlock
                      language=javascript-listing@10
                      <>
                        \"console.log('test');\"
                ",
      expected: "
                  <> root
                    <> pre
                      language=javascript
                      class=listing
                      style=counter-set:listing 9
                      <>
                        \"console.log('test');\"
                ",
    ),
    infra.AssertiveTestDataNoParam(
      source:   "
                  <> root
                    <> CodeBlock
                      language=listing@3
                      <>
                        \"line one\"
                        \"line two\"
                ",
      expected: "
                  <> root
                    <> pre
                      class=listing
                      style=counter-set:listing 2
                      <>
                        \"line one\"
                        \"line two\"
                ",
    ),
    infra.AssertiveTestDataNoParam(
      source:   "
                  <> root
                    <> CodeBlock
                      <>
                        \"plain code block\"
                ",
      expected: "
                  <> root
                    <> pre
                      <>
                        \"plain code block\"
                ",
    ),
  ]
}

pub fn assertive_tests() {
  infra.assertive_test_collection_from_data_no_param(name, assertive_tests_data(), constructor)
}
