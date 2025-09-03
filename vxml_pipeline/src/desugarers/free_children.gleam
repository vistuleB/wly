import gleam/option
import gleam/string.{inspect as ins}
import infrastructure.{type Desugarer, Desugarer, type DesugarerTransform, type DesugaringError} as infra
import nodemaps_2_desugarer_transforms as n2t
import vxml.{type VXML, V}

fn nodemap(
  node: VXML,
  inner: InnerParam,
) -> List(VXML) {
  case node {
    V(blame, tag, attributes, children) if tag == inner.1 -> {
      children
      |> infra.either_or_misceginator(infra.is_v_and_tag_equals(_, inner.0))
      |> infra.regroup_ors
      |> infra.map_either_ors(
        fn(either: VXML) -> VXML { either },
        fn(or: List(VXML)) -> VXML { V(blame, tag, attributes, or) },
      )
    }
    _ -> [node]
  }
}

fn nodemap_factory(inner: InnerParam) -> n2t.OneToManyNoErrorNodeMap {
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
/// given a parent-child structure of the form
///
///     A[parent]
///
///         B[child]
///
///         C[child]
///
///         B[child]
///
///         D[child]
///
///         C[child]
///
///         B[child]
///
/// where A, B, C, D represent tags, a call to
///
/// free_children(#(A, C))
///
/// will for example result in the updated
/// structure
///
///     A[parent]
///
///         B[child]
///
///     C[parent]
///
///     A[parent]
///
///         B[child]
///
///         D[child]
///
///     C[parent]
///
///     A[parent]
///
///         B[child]
///
/// with the original attribute values of A
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
fn assertive_tests_data() -> List(infra.AssertiveTestData(Param)) {
  []
}

pub fn assertive_tests() {
  infra.assertive_test_collection_from_data(name, assertive_tests_data(), constructor)
}
