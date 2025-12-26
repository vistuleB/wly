import gleam/list
import gleam/option
import gleam/string.{inspect as ins}
import infrastructure.{
  type Desugarer,
  type DesugarerTransform,
  type DesugaringError,
  Desugarer,
} as infra
import nodemaps_2_desugarer_transforms as n2t
import vxml.{type VXML, T, V}

type TopOfStack {
  Nothing
  Hot(VXML)
  Cold(VXML)
}

type Stack = #(List(VXML), TopOfStack)

fn smash_cold_t(
  stack: Stack,
  smashee: VXML,
) -> Stack {
  let assert T(..) = smashee
  let #(previous, t) = stack
  case t {
    Hot(t) -> {
      let smashee = infra.t_t_last_to_first_concatenation(t, smashee)
      #(previous, Cold(smashee))
    }
    Cold(t) -> #([t, ..previous], Cold(smashee))
    Nothing -> #(previous, Cold(smashee))
  }
}

fn smash_cold_v(
  stack: Stack,
  smashee: VXML,
) -> Stack {
  let assert V(..) = smashee
  let #(previous, t) = stack
  case t {
    Hot(t) | Cold(t) -> #([smashee, t, ..previous], Nothing)
    Nothing -> #([smashee, ..previous], Nothing)
  }
}

fn smash_hot(
  stack: Stack,
  smashees: List(VXML),
) -> Stack {
  let #(previous, t) = stack
  let #(previous, t) = case t, smashees {
    Hot(t), [T(..) as first, ..rest] | Cold(t), [T(..) as first, ..rest] -> {
      let t = infra.t_t_last_to_first_concatenation(t, first)
      case rest {
        [] -> #(previous, t)
        _ -> infra.pour_but_last(rest, [t, ..previous])
      }
    }
    Hot(t), _ | Cold(t), _ -> infra.pour_but_last(smashees, [t, ..previous])
    Nothing, _ -> infra.pour_but_last(smashees, previous)
  }
  case t {
    T(..) -> #(previous, Hot(t))
    _ -> #([t, ..previous], Nothing)
  }
}

fn accumulator(
  inner: InnerParam,
  stack: Stack,
  remaining: List(VXML),
) -> List(VXML) {
  case remaining {
    [] -> case stack {
      #(previous, Nothing) -> previous |> list.reverse
      #(previous, Hot(t)) -> [t, ..previous] |> list.reverse
      #(previous, Cold(t)) -> [t, ..previous] |> list.reverse
    }
    [T(..) as first, ..rest] -> {
      let stack = smash_cold_t(stack, first)
      accumulator(inner, stack, rest)
    }
    [V(_, tag, _, children) as first, ..rest] -> {
      case tag == inner.0 && inner.1(first) {
        False -> {
          let stack = smash_cold_v(stack, first)
          accumulator(inner, stack, rest)
        }
        True -> {
          let stack = smash_hot(stack, children)
          accumulator(inner, stack, rest)
        }
      }
    }
  }
}

fn nodemap(
  node: VXML,
  inner: InnerParam,
) -> VXML {
  case node {
    V(_, _, _, children) -> {
      let children = accumulator(inner, #([], Nothing), children)
      V(..node, children: children)
    }
    _ -> node
  }
}

fn nodemap_factory(inner: InnerParam) -> n2t.OneToOneNoErrorNodemap {
  nodemap(_, inner)
}

fn transform_factory(inner: InnerParam) -> DesugarerTransform {
  nodemap_factory(inner)
  |> n2t.one_to_one_no_error_nodemap_2_desugarer_transform
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(param)
}

type Param = #(String, fn(VXML) -> Bool)
type InnerParam = Param

pub const name = "fold_children_into_text_if"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// Replaces a specified tag (except if it occurs
/// at the root) by its children and stitches the
/// first and last children to surrounding text in
/// last_to_first fashion.
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
  []
}

pub fn assertive_tests() {
  infra.assertive_test_collection_from_data(name, assertive_tests_data(), constructor)
}
