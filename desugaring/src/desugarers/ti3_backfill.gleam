import gleam/option
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
import vxml.{type VXML, V, Attribute}
import blame as bl
import on

const const_blame = bl.Des([], "ti3_backfill", 23)

const stub_sub =
  V(
    const_blame,
    "Sub",
    [Attribute(const_blame, "title", "Lorem Ipsum")],
    [],
  )

const stub_chapter =
  V(
    const_blame,
    "Chapter",
    [Attribute(const_blame, "title", "Lorem Ipsum")],
    [],
  )

fn backfill_elements(
  children: List(VXML),
  stub: VXML,
) -> Result(List(VXML), DesugaringError) {
  let assert V(_, stub_tag, _, _) = stub
  use #(_, children) <- on.ok(
    list.try_fold(
      children,
      #(0, []),
      fn(acc, child) {
        case child {
          V(blame, t, _, _) if t == stub_tag -> {
            use number <- on.lazy_none_some(
              infra.v_value_of_first_attribute_with_key(child, "should-be-number"),
              fn() { Error(DesugaringError(blame, "expecting 'should-be-number' attribute on each " <> stub_tag <> " element")) },
            )
            use number <- on.error_ok(
              int.parse(number),
              fn(_) { Error(DesugaringError(blame, "could not parse should-be-number attribute as integer")) }
            )
            use <- on.lazy_true_false(
              number <= acc.0,
              fn() { Error(DesugaringError(blame, "expecting monotone subchapter numbers (" <> ins(number) <> " <= " <> ins(acc.0) <> ")")) }
            )
            let fill = list.repeat(stub, number - acc.0 - 1)
            let prev = list.append(fill, acc.1)
            Ok(#(number, [child, ..prev]))
          }
          _ -> Ok(#(acc.0, [child, ..acc.1]))
        }
      }
    )
  )
  Ok(children |> list.reverse)
}

fn nodemap(
  node: VXML,
) -> Result(#(VXML, TrafficLight), DesugaringError) {
  case node {
    V(_, "Chapter", _, children) -> {
      use children <- on.ok(backfill_elements(children, stub_sub))
      Ok(#(V(..node, children: children), GoBack))
    }
    V(_, _, _, children) -> {
      use children <- on.ok(backfill_elements(children, stub_chapter))
      Ok(#(V(..node, children: children), Continue))
    }
    _ -> panic as "how could we see anything except 'Chapter' and root, if 'Chapter' orders GoBack?"
  }
}

fn nodemap_factory(_inner: InnerParam) -> n2t.EarlyReturnOneToOneNodeMap {
  nodemap(_)
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

pub const name = "ti3_backfill"

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
