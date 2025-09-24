import gleam/list
import gleam/option
import gleam/string.{inspect as ins}
import infrastructure.{type Desugarer, Desugarer, type DesugarerTransform, type DesugaringError, DesugaringError} as infra
import nodemaps_2_desugarer_transforms as n2t
import vxml.{type VXML, T, V}
import on

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

fn smash_hot_t(
  stack: Stack,
  smashee: VXML,
) -> Stack {
  let assert T(..) = smashee
  let #(previous, t) = stack
  case t {
    Hot(t) | Cold(t) -> {
      let smashee = infra.t_t_last_to_first_concatenation(t, smashee)
      #(previous, Hot(smashee))
    }
    Nothing -> #(previous, Hot(smashee))
  }
}

fn accumulator(
  inner: InnerParam,
  stack: Stack,
  remaining: List(VXML),
) -> Result(List(VXML), DesugaringError) {
  case remaining {
    [] -> case stack {
      #(previous, Nothing) -> previous |> list.reverse |> Ok
      #(previous, Hot(t)) -> [t, ..previous] |> list.reverse |> Ok
      #(previous, Cold(t)) -> [t, ..previous] |> list.reverse |> Ok
    }
    [T(..) as first, ..rest] -> {
      let stack = smash_cold_t(stack, first)
      accumulator(inner, stack, rest)
    }
    [V(_, tag, _, children) as first, ..rest] -> {
      case list.contains(inner, tag) {
        False -> {
          let stack = smash_cold_v(stack, first)
          accumulator(inner, stack, rest)
        }
        True -> {
          use t <- on.ok(case children {
            [T(..) as one] -> Ok(one)
            _ -> Error(DesugaringError(first.blame, "found " <> ins(list.length(children)) <> " ≠ 1 child or non-T nodes"))
          })
          let stack = smash_hot_t(stack, t)
          accumulator(inner, stack, rest)
        }
      }
    }
  }
}

fn nodemap(
  node: VXML,
  inner: InnerParam,
) -> Result(VXML, DesugaringError) {
  case node {
    V(_, _, _, children) -> {
      use children <- on.ok(accumulator(inner, #([], Nothing), children))
      Ok(V(..node, children: children))
    }
    _ -> Ok(node)
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

type Param = List(String)
type InnerParam = Param

pub const name = "fold_contents_into_text__batch"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// Replaces a specified tag by its contents
/// assuming that the tag contains exactly one child
/// consisting of text.
///
/// The text content gets folded into surrounding text
/// nodes (in end-of-last-line to beginning-of-first-line
/// fashion).
///
/// Throws an error if any instance of the tag fails
/// to have exactly one text child.
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
