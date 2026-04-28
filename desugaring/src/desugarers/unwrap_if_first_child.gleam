import gleam/list
import gleam/option
import gleam/string.{inspect as ins}
import infrastructure.{type Desugarer, Desugarer, type DesugarerTransform, type DesugaringError} as infra
import nodemaps_2_desugarer_transforms as n2t
import vxml.{type VXML, V}

fn nodemap(
  node: VXML,
  previous_siblings: List(VXML),
  inner: InnerParam,
) -> List(VXML) {
  case node {
    V(_, tag, _, children) if tag == inner -> {
      // We check if all previous siblings are whitespace text nodes
      case list.all(previous_siblings, infra.is_t_and_is_whitespace) {
        True -> children
        False -> [node]
      }
    }
    _ -> [node]
  }
}

fn nodemap_factory(inner: InnerParam) -> n2t.FancyOneToManyNoErrorNodemap {
  fn(
    vxml: VXML,
    _: List(VXML),
    _: List(VXML),
    previous_siblings_after_mapping: List(VXML),
    _: List(VXML),
  ) {
    nodemap(vxml, previous_siblings_after_mapping, inner)
  }
}

fn transform_factory(inner: InnerParam) -> DesugarerTransform {
  nodemap_factory(inner)
  |> n2t.fancy_one_to_many_no_error_nodemap_2_desugarer_transform()
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(param)
}

type Param = String
//             ↖
//             tag to be unwrapped if it's the first child
type InnerParam = Param

pub const name = "unwrap_if_first_child"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// Unwraps a given tag when it is the first 
/// non-whitespace child of its parent. Because the 
/// transformation is applied depth-first and the 
/// fancy transform handles the children first, it 
/// effectively unwraps multiple levels of the same 
/// tag if they are nested at the start.
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
      param: "WriterlyBlankLine",
      source: "
                <> Proof
                  <> WriterlyBlankLine
                  <> WriterlyBlankLine
                  <>
                    'some text'
                ",
      expected: "
                <> Proof
                  <>
                    'some text'
                ",
    ),
    infra.AssertiveTestData(
      param: "WriterlyBlankLine",
      source: "
                <> div
                  <> p
                    <>
                      'Text'
                  <> WriterlyBlankLine
                  <>
                    'More'
                ",
      expected: "
                <> div
                  <> p
                    <>
                      'Text'
                  <> WriterlyBlankLine
                  <>
                    'More'
                ",
    ),
    infra.AssertiveTestData(
      param: "span",
      source: "
                <> div
                  <> span
                    <> span
                      <>
                        'Inside'
                ",
      expected: "
                <> div
                  <>
                    'Inside'
                ",
    ),
  ]
}

pub fn assertive_tests() {
  infra.assertive_test_collection_from_data(name, assertive_tests_data(), constructor)
}
