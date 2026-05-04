import gleam/list
import gleam/option
import gleam/string.{inspect as ins}
import infrastructure.{type Desugarer, Desugarer, type DesugarerTransform, type DesugaringError} as infra
import nodemaps_2_desugarer_transforms as n2t
import vxml.{type VXML, T, Line}

fn nodemap(
  vxml: VXML,
  ancestors: List(VXML),
  inner: InnerParam,
) -> VXML {
  case vxml {
    T(blame, lines) -> {
      let #(ancestor_tags, if_pair, else_pair) = inner
      
      let has_ancestor = list.any(ancestors, fn(a) { 
        list.contains(ancestor_tags, infra.v_get_tag(a))
      })

      let #(from, to) = case has_ancestor {
        True -> if_pair
        False -> else_pair
      }

      let new_lines =
        list.map(lines, fn(line) {
          Line(..line, content: string.replace(line.content, from, to))
        })
      T(blame, new_lines)
    }
    _ -> vxml
  }
}

fn nodemap_factory(inner: InnerParam) -> n2t.FancyOneToOneNoErrorNodemap {
  fn(vxml, ancestors, _s1, _s2, _s3) {
    nodemap(vxml, ancestors, inner)
  }
}

fn transform_factory(inner: InnerParam) -> DesugarerTransform {
  n2t.fancy_one_to_one_no_error_nodemap_2_desugarer_transform(nodemap_factory(inner))
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(param)
}

type Param = #(List(String), #(String, String), #(String, String))
//             ↖             ↖                ↖
//             ancestors     if version       else version
type InnerParam = Param

pub const name = "find_replace_if_has_ancestor_else"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// replaces literal occurrences of a string with another 
/// based on whether the text node has any of the specified ancestors
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
fn assertive_tests_data() -> List(infra.AssertiveTestData(Param)) {
  [
    infra.AssertiveTestData(
      param: #(["special"], #("``", "“"), #("``", "`")),
      source: "
                <> root
                  <> special
                    <>
                      'First line ``'
                      'Second line ``'
                  <> ordinary
                    <>
                      'Outside special ``'
                ",
      expected: "
                <> root
                  <> special
                    <>
                      'First line “'
                      'Second line “'
                  <> ordinary
                    <>
                      'Outside special `'
                ",
    ),
  ]
}

pub fn assertive_tests() {
  infra.assertive_test_collection_from_data(name, assertive_tests_data(), constructor)
}
