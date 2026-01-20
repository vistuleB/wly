import gleam/list
import gleam/option
import gleam/string.{inspect as ins}
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
import nodemaps_2_desugarer_transforms as n2t
import vxml.{type VXML, V}
import blame as bl

fn wrap_in_list(
  already_wrapped: List(VXML),
  currently_being_wrapped: List(VXML),
  upcoming: List(VXML),
  inner: InnerParam,
) -> List(VXML) {
  case upcoming {
    [] -> case currently_being_wrapped {
      [] -> already_wrapped |> list.reverse
      _ -> {
        let wrap = V(desugarer_blame(28), inner.1, [], currently_being_wrapped |> list.reverse)
        [wrap, ..already_wrapped] |> list.reverse
      }
    }
    [V(_, tag, _, _) as first, ..rest] if tag == inner.2 -> case currently_being_wrapped {
      [] -> wrap_in_list([first, ..already_wrapped], [], rest, inner)
      _ -> {
        let wrap = V(desugarer_blame(35), inner.1, [], currently_being_wrapped |> list.reverse)
        wrap_in_list([first, wrap, ..already_wrapped ], [], rest, inner)
      }
    }
    [first, ..rest] -> wrap_in_list(already_wrapped, [first, ..currently_being_wrapped], rest, inner)
  }
}

fn nodemap(
  node: VXML,
  inner: InnerParam,
) -> #(VXML, TrafficLight) {
  case node {
    V(_, tag, _, children) if tag == inner.0 -> {
      let children = wrap_in_list([], [], children, inner)
      #(V(..node, children: children), inner.3)
    }
    _ -> #(node, Continue)
  }
}

fn nodemap_factory(inner: InnerParam) -> n2t.EarlyReturnOneToOneNoErrorNodemap {
  nodemap(_, inner)
}

fn transform_factory(inner: InnerParam) -> DesugarerTransform {
  nodemap_factory(inner)
  |> n2t.early_return_one_to_one_no_error_nodemap_2_desugarer_transform()
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  case infra.valid_tag(param.1) {
    True -> Ok(param)
    False -> Error(DesugaringError(bl.no_blame, "invalid tag for wrapper"))
  }
}

type Param = #(String,  String,   String,    TrafficLight)
//             ↖        ↖         ↖
//             parent   wrapper   avoiding
//             tag      tag       tag
type InnerParam = Param

pub const name = "wrap_children_avoiding"
fn desugarer_blame(line_no: Int) { bl.Des([], name, line_no) }

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// For a specified parent tag, wraps consecutive
/// children that do not have the 'to avoid' tag
/// in a given wrapper tag.
///
/// The 'to avoid' tag children remain  unwrapped.
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
      param: #("parent", "wrapper", "avoid_me", GoBack),
      source:   "
                <> root
                  <> parent
                    <> p
                    <> q
                    <> avoid_me
                    <> avoid_me
                    <> q
                ",
      expected: "
                <> root
                  <> parent
                    <> wrapper
                      <> p
                      <> q
                    <> avoid_me
                    <> avoid_me
                    <> wrapper
                      <> q
                ",
    ),
    infra.AssertiveTestData(
      param: #("parent", "wrapper", "avoid_me", GoBack),
      source:   "
                <> root
                  <> parent
                    <> avoid_me
                    <> p1
                    <> p2
                    <> p3
                    <> avoid_me
                ",
      expected: "
                <> root
                  <> parent
                    <> avoid_me
                    <> wrapper
                      <> p1
                      <> p2
                      <> p3
                    <> avoid_me
                ",
    ),
  ]
}

pub fn assertive_tests() {
  infra.assertive_test_collection_from_data(name, assertive_tests_data(), constructor)
}
