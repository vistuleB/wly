import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
  type TrafficLight, Continue, DesugaringError, GoBack,
}
import desugaring/nodemaps_2_transform as n2t
import gleam/int
import gleam/list
import gleam/option.{Some}
import gleam/regexp.{type Regexp}
import gleam/string.{inspect as ins}
import on
import vxml.{type VXML, V}
import vxml/blame as bl

pub const name = "ti2_add_should_be_numbers"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Extracts chapter and subchapter numbers from source
/// paths and stores them as `should-be-number` attrs.
pub fn constructor() -> Desugarer {
  authoring.no_param_desugarer(
    name: name,
    transform: inner_param_to_transform(),
  )
}

fn process_sub(node: VXML, inner: InnerParam) -> Result(VXML, DesugaringError) {
  case node {
    V(blame, "Sub", _, _) -> {
      let assert bl.Src(_, path, _, _, _) = blame
      use first, _ <- on.empty_nonempty(regexp.scan(inner.1, path), fn() {
        Error(DesugaringError(
          blame,
          "cannot not read subchapter number in blame path: " <> path,
        ))
      })
      let assert [Some(x)] = first.submatches
      let assert Ok(x) = int.parse(x)
      Ok(core.v_set_attr(node, desugarer_blame(43), "should-be-number", ins(x)))
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
      let assert bl.Src(_, path, _, _, _) = blame
      use first, _ <- on.empty_nonempty(regexp.scan(inner.0, path), fn() {
        Error(DesugaringError(blame, "cannot read directory number"))
      })
      let assert [Some(x)] = first.submatches
      let assert Ok(x) = int.parse(x)
      use children <- on.ok(list.try_map(children, process_sub(_, inner)))
      let attrs =
        core.attrs_set(attrs, desugarer_blame(63), "should-be-number", ins(x))
      Ok(#(V(..node, attrs: attrs, children: children), GoBack))
    }
    _ -> Ok(#(node, Continue))
  }
}

fn nodemap_factory(inner: InnerParam) -> n2t.EarlyReturnOneToOneNodemap {
  nodemap(_, inner)
}

fn inner_param_to_transform() -> DesugarerTransform {
  let inner = param_to_inner_param()
  nodemap_factory(inner)
  |> n2t.early_return_one_to_one_nodemap_2_desugarer_transform
}

fn param_to_inner_param() -> InnerParam {
  let assert Ok(re_chapter) = regexp.from_string("(\\d\\d)\\/")
  let assert Ok(re_sub) = regexp.from_string("\\d\\d/(\\d\\d)-")
  #(re_chapter, re_sub)
}

fn desugarer_blame(line_no: Int) {
  bl.Des([], name, line_no)
}

type InnerParam =
  #(Regexp, Regexp)

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
fn assertive_tests_data() -> List(core.AssertiveTestDataNoParam) {
  []
}

pub fn assertive_tests() {
  core.assertive_test_collection_from_data_no_param(
    name,
    assertive_tests_data(),
    constructor,
  )
}
