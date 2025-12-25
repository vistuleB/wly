import gleam/option.{Some, None}
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
import on

fn nodemap(
  vxml: VXML,
  inner: InnerParam,
) -> Result(VXML, DesugaringError) {
  case vxml {
    V(blame, tag, attrs, _) -> {
      case list.contains(inner, tag) {
        False -> Ok(vxml)
        True -> {
          use #(info, attrs) <- on.ok(infra.attrs_extract_unique_key_or_none(attrs, "info"))
          use info <- on.none_some(info, fn() { Ok(vxml) })
          use #(language, id, class, style) <- on.error_ok(
            infra.expand_clode_block_info_html_shorthand(info.blame, info.val),
            fn(msg) { Error(DesugaringError(blame, msg)) }
          )
          use attrs <- on.ok(case attrs {
            [] -> Ok([language, id, class, style] |> option.values)
            _ -> {
              let mergeable = [id, class, style] |> option.values
              let attrs = case mergeable {
                [] -> attrs
                _ -> infra.merge_attrs(list.append(attrs, mergeable))
              }
              case language {
                None -> Ok(attrs)
                Some(language) -> case infra.attrs_first_with_key(attrs, "language") {
                  None -> Ok([language, ..attrs])
                  Some(x) -> case x.val == language.val {
                    True -> Ok(attrs)
                    False -> Error(DesugaringError(blame, "duplicate 'language' via info tag & pre-existing attribute"))
                  }
                }
              }
            }
          })
          Ok(V(..vxml, attrs: attrs))
        }
      }
    }
    _ -> Ok(vxml)
  }
}

fn nodemap_factory(inner: InnerParam) -> n2t.OneToOneNodeMap {
  nodemap(_, inner)
}

fn transform_factory(inner: InnerParam) -> DesugarerTransform {
  nodemap_factory(inner)
  |> n2t.one_to_one_nodemap_2_desugarer_transform
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(param)
}

pub const name = "expand_info_attribute"

type Param = List(String)
type InnerParam = Param

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// For tags in the given list (typically "pre" and/or
/// "WriterlyCodeBlock" and/or "CodeBlock", depending)
/// replace the attribute with key "info" by separate
/// 'language', 'id', 'class', and 'style' attributes,
/// according to the following schema:
/// 
/// - anything before the first '.' or '#' in in the
///   info attribute becomes the language
/// - anything after a '.' and the next '.' or '#'
///   becomes a class, unless it contains at least one
///   occurrence of ':', in which case it becomes a style
/// - anything after a '#' and the next '.' or '#'
///   becomes an id (hopefully unique, or else an error
///   is thrown
/// 
/// Parsed styles overwrite existing styles, if any.
/// 
/// Id conflicts results in a DesugaringError.
pub fn constructor(param: Param) -> Desugarer {
  Desugarer(
    name: name,
    stringified_param: option.None,
    stringified_outside: option.None,
    transform: case param_to_inner_param(param) {
      Error(error) -> fn(_) { Error(error) }
      Ok(inner) -> transform_factory(inner)
    },
  )
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
fn assertive_tests_data() -> List(infra.AssertiveTestData(Param)) {
  [
    infra.AssertiveTestData(
      param: ["pre"],
      source:   "
                  <> root
                    <> pre
                      info=python.listing
                      <>
                        'plain code block'
                ",
      expected: "
                  <> root
                    <> pre
                      language=python
                      class=listing
                      <>
                        'plain code block'
                ",
    ),
    infra.AssertiveTestData(
      param: ["pre"],
      source:   "
                  <> root
                    <> pre
                      info=python.listing#bob
                      <>
                        'plain code block'
                ",
      expected: "
                  <> root
                    <> pre
                      language=python
                      id=bob
                      class=listing
                      <>
                        'plain code block'
                ",
    ),
    infra.AssertiveTestData(
      param: ["pre"],
      source:   "
                  <> root
                    <> pre
                      info=python.listing#bob.background-color:taupe
                      <>
                        'plain code block'
                ",
      expected: "
                  <> root
                    <> pre
                      language=python
                      id=bob
                      class=listing
                      style=background-color:taupe
                      <>
                        'plain code block'
                ",
    ),
    infra.AssertiveTestData(
      param: ["pre"],
      source:   "
                  <> root
                    <> pre
                      info=.listing
                      <>
                        'plain code block'
                ",
      expected: "
                  <> root
                    <> pre
                      class=listing
                      <>
                        'plain code block'
                ",
    ),
  ]
}

pub fn assertive_tests() {
  infra.assertive_test_collection_from_data(name, assertive_tests_data(), constructor)
}
