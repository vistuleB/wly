import gleam/option.{Some}
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
import vxml.{type VXML, V}
import blame as bl
import on

fn process_sub(
  node: VXML,
  inner: InnerParam,
) -> Result(VXML, DesugaringError) {
  case node {
    V(blame, "Sub", _, _) -> {
      let assert bl.Src(_, path, _, _) = blame
      use first, _ <- on.lazy_empty_nonempty(
        regexp.scan(inner.1, path),
        fn() { Error(DesugaringError(blame, "cannot not read subchapter number in blame path: " <> path)) },
      )
      let assert [Some(x)] = first.submatches
      let assert Ok(x) = int.parse(x)
      Ok(infra.v_set_attribute(node, desugarer_blame(34), "should-be-number", ins(x)))
    }
    _ -> Ok(node)
  }
}

fn nodemap(
  node: VXML,
  inner: InnerParam,
) -> Result(#(VXML, TrafficLight), DesugaringError) {
  case node {
    V(blame, "Chapter", attrs, children) -> {
      let assert bl.Src(_, path, _, _) = blame
      use first, _ <- on.lazy_empty_nonempty(
        regexp.scan(inner.0, path),
        fn() { Error(DesugaringError(blame, "cannot read directory number")) },
      )
      let assert [Some(x)] = first.submatches
      let assert Ok(x) = int.parse(x)
      use children <- on.ok(list.try_map(children, process_sub(_, inner)))
      let attrs = infra.attributes_set(attrs, desugarer_blame(54), "should-be-number", ins(x))
      Ok(#(V(..node, attributes: attrs, children: children), GoBack))
    }
    _ -> Ok(#(node, Continue))
  }
}

fn nodemap_factory(inner: InnerParam) -> n2t.EarlyReturnOneToOneNodeMap {
  nodemap(_, inner)
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

pub const name = "ti3_add_should_be_numbers"
fn desugarer_blame(line_no: Int) { bl.Des([], name, line_no) }

type Param = Nil
type InnerParam = #(Regexp, Regexp)

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// Processes CodeBlock elements with
/// language=python-prompt and converts them to pre
/// elements with proper span highlighting for
/// prompts, responses, and errors
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
  []
}

pub fn assertive_tests() {
  infra.assertive_test_collection_from_data_no_param(name, assertive_tests_data(), constructor)
}
