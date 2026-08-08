import desugaring/core.{
  type AssertiveTestData, type Desugarer, type DesugarerTransform,
  type DesugaringError, AssertiveTestData, Desugarer,
} as core
import desugaring/nodemaps_2_transform as n2t
import gleam/list
import gleam/option
import gleam/string.{inspect as ins}
import vxml.{type VXML, Attr, T, V}

// add `class_name` to a node's `class` attribute (appending, or creating it)
fn add_class(node: VXML, class_name: String) -> VXML {
  case node {
    T(_, _) -> node
    V(b, tag, attrs, children) ->
      case list.any(attrs, fn(a) { a.key == "class" }) {
        True ->
          V(
            b,
            tag,
            list.map(attrs, fn(a) {
              case a.key == "class" {
                True -> Attr(..a, val: a.val <> " " <> class_name)
                False -> a
              }
            }),
            children,
          )
        False -> V(b, tag, [Attr(b, "class", class_name), ..attrs], children)
      }
  }
}

fn rewrite(children: List(VXML), inner: InnerParam) -> List(VXML) {
  let #(marker, class_name) = inner
  case children {
    [] -> []
    [V(_, tag, _, _), next, ..rest] if tag == marker -> [
      add_class(next, class_name),
      ..rewrite(rest, inner)
    ]
    // a marker with no following sibling is simply dropped
    [V(_, tag, _, _)] if tag == marker -> []
    [first, ..rest] -> [first, ..rewrite(rest, inner)]
  }
}

fn nodemap(node: VXML, inner: InnerParam) -> VXML {
  case node {
    V(_, _, _, children) -> V(..node, children: rewrite(children, inner))
    _ -> node
  }
}

fn nodemap_factory(inner: InnerParam) -> n2t.OneToOneNoErrorNodemap {
  nodemap(_, inner)
}

fn transform_factory(inner: InnerParam) -> DesugarerTransform {
  nodemap_factory(inner)
  |> n2t.one_to_one_no_error_nodemap_2_desugarer_transform()
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(param)
}

type Param =
  #(String, String)

//  ↖         ↖
//  marker    class to add to the marker's
//  tag       immediately-following sibling
type InnerParam =
  Param

pub const name = "add_class_to_next_sibling"

//------------------------------------------------53
/// For each child that is a `marker`-tagged node, append `class_name` to the
/// class attribute of its immediately-following sibling and delete the marker.
/// (Used for `|> Indent`: it drops the marker and tags the next paragraph with
/// an `indent` class.)
pub fn constructor(param: Param) -> Desugarer {
  Desugarer(
    name: name,
    stringified_param: option.Some(ins(param)),
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
fn assertive_tests_data() -> List(AssertiveTestData(Param)) {
  [
    AssertiveTestData(
      param: #("Indent", "indent"),
      source: "
                <> Root
                  <> Indent
                  <> p
                    <>
                      'hello'
              ",
      expected: "
                <> Root
                  <> p
                    class=indent
                    <>
                      'hello'
              ",
    ),
    AssertiveTestData(
      param: #("Indent", "indent"),
      source: "
                <> Root
                  <> p
                    class=existing
                  <> Indent
                  <> p
              ",
      expected: "
                <> Root
                  <> p
                    class=existing
                  <> p
                    class=indent
              ",
    ),
  ]
}

pub fn assertive_tests() {
  core.assertive_test_collection_from_data(
    name,
    assertive_tests_data(),
    constructor,
  )
}
