import gleam/option
import gleam/string.{inspect as ins}
import desugaring/core.{type Desugarer, Desugarer, type DesugarerTransform, type DesugaringError} as core
import desugaring/nodemaps_2_transform as n2t
import vxml.{type VXML, V}
import either_or as eo

fn nodemap(
  node: VXML,
  inner: InnerParam,
) -> List(VXML) {
  case node {
    V(blame, tag, attrs, children) if tag == inner.1 -> {
      children
      |> eo.discriminate(core.is_v_and_tag_equals(_, inner.0))
      |> eo.group_ors
      |> eo.map_resolve(
        fn(either: VXML) -> VXML { either },
        fn(or: List(VXML)) -> VXML { V(blame, tag, attrs, or) },
      )
    }
    _ -> [node]
  }
}

fn nodemap_factory(inner: InnerParam) -> n2t.OneToManyNoErrorNodemap {
  nodemap(_, inner)
}

fn transform_factory(inner: InnerParam) -> DesugarerTransform {
  nodemap_factory(inner)
  |> n2t.one_to_many_no_error_nodemap_2_desugarer_transform()
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(param)
}

type Param = #(String,      String)
//             ↖            ↖
//             tag of       ...when
//             child to     parent is
//             free from    this tag
//             parent
type InnerParam = Param

pub const name = "free_children"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// given a VXML of the form
///
/// <> root
///   <> A
///     <> B
///     <> C
///     <> B
///     <> D
///     <> C
///     <> B
///
/// a call to
///
///   free_children(#(A, C))
///
/// will result in the updated structure
///
/// <> root
///   <> A
///     <> B
///   <> C
///   <> A
///     <> B
///     <> D
///   <> C
///   <> A
///     <> B
///
/// with the original attr values of A
/// copied over to the newly created 'copies' of
/// A
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
fn assertive_tests_data() -> List(core.AssertiveTestData(Param)) {
  []
}

pub fn assertive_tests() {
  core.assertive_test_collection_from_data(name, assertive_tests_data(), constructor)
}
