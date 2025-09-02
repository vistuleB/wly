import gleam/list
import gleam/option
import gleam/string.{inspect as ins}
import infrastructure.{type Desugarer, Desugarer, type DesugarerTransform, type DesugaringError} as infra
import nodemaps_2_desugarer_transforms as n2t
import vxml.{type VXML, T, V}
import on

fn wrap_second_element_if_its_math_and_recurse(
  children: List(VXML),
  inner: InnerParam,
) -> List(VXML) {
  let #(to_be_wrapped, wrapper_tag) = inner

  use first, after_first <- on.empty_nonempty(
    children,
    []
  )

  use second, after_second <- on.empty_nonempty(
    after_first,
    children
  )

  use <- on.lazy_false_true(
    infra.is_v_and_tag_equals(second, to_be_wrapped),
    fn() {
      [
        first,
        ..wrap_second_element_if_its_math_and_recurse([second, ..after_second], inner)
      ]
    },
  )

  let #(first, last_word_of_first) =
    infra.extract_last_word_from_t_node_if_t(first)

  use third, after_third <- on.lazy_empty_nonempty(
    after_second,
    fn() {
      case last_word_of_first {
        option.None -> [
          first,
          ..wrap_second_element_if_its_math_and_recurse([second, ..after_second], inner)
        ]
        option.Some(t_node) -> [
          first,
          V(
            second.blame,
            wrapper_tag,
            [],
            [t_node, second],
          ),
          ..wrap_second_element_if_its_math_and_recurse(after_second, inner)
        ]
      }
    }
  )

  let #(first_word_of_third, third) =
    infra.extract_first_word_from_t_node_if_t(third)

  case option.is_some(last_word_of_first) || option.is_some(first_word_of_third) {
    True -> [
      first,
      V(
        second.blame,
        wrapper_tag,
        [],
        [last_word_of_first, option.Some(second), first_word_of_third]
        |> option.values,
      ),
      ..wrap_second_element_if_its_math_and_recurse([third, ..after_third], inner)
    ]
    False -> [
      first,
      ..wrap_second_element_if_its_math_and_recurse([second, ..after_second], inner)
    ]
  }
}

fn nodemap(
  node: VXML,
  inner: InnerParam,
) -> Result(VXML, DesugaringError) {
  case node {
    T(_, _) -> Ok(node)
    V(b, t, a, children) -> {
      Ok(V(
        b,
        t,
        a,
        [V(b, "Dummy", [], []), ..children]
          |> wrap_second_element_if_its_math_and_recurse(inner)
          |> list.drop(1),
      ))
    }
  }
}

fn nodemap_factory(inner: InnerParam) -> n2t.OneToOneNodeMap {
  nodemap(_, inner)
}

fn transform_factory(inner: InnerParam) -> DesugarerTransform {
  n2t.one_to_one_nodemap_2_desugarer_transform(nodemap_factory(inner))
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(param)
}

type Param = #(String,     String)
//             ↖           ↖
//             tag to      wrapper tag
//             be wrapped
type InnerParam = Param

pub const name = "wrap_adjacent_non_whitespace_text_with"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// Globs all non-whitespace characters surrounding
/// a given kind of element A and wraps those
/// characters plus the element A itself into a
/// wrapper element B. For example:
///
/// BEFORE:
/// ```
/// <>
///   "some text that ends right"
///   "here with an m-dash: —"
/// <> A
/// <>
///   ", more text that started with a comma"
/// ```
///
/// AFTER:
/// ```
/// <>
///   "some text that ends right"
///   "here with an m-dash: "
/// <> B
///   <>
///     "—"
///   <> A
///   <>
///     ","
/// <>
///   " more text that started with a comma"
/// ```
///
/// If no text is found to glob A in, leaves A
/// unwrapped.
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
