import gleam/list
import gleam/option
import gleam/string.{inspect as ins}
import desugaring/core.{
  type Desugarer,
  type DesugarerTransform,
  type DesugaringError,
  Desugarer,
} as core
import desugaring/nodemaps_2_transform as n2t
import vxml.{
  type VXML,
  V,
  Attr,
}

fn nodemap(
  vxml: VXML,
  inner: InnerParam,
) -> VXML {
  case vxml {
    V(_, _, attrs, _) -> V(..vxml, attrs: list.map(attrs, fn(attr) {
      case attr.key == inner.0 {
        False -> attr
        True -> {
          let val = list.fold(
            inner.1,
            attr.val,
            fn(acc, prefix) { core.drop_prefix(acc, prefix) }
          )
          Attr(..attr, val: val)
        }
      }
    }))
    _ -> vxml
  }
}

fn nodemap_factory(inner: InnerParam) -> n2t.OneToOneNoErrorNodemap {
  nodemap(_, inner)
}

fn transform_factory(inner: InnerParam) -> DesugarerTransform {
  nodemap_factory(inner)
  |> n2t.one_to_one_no_error_nodemap_2_desugarer_transform()
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(param)
}

type Param = #(String,     List(String))
//             ↖           ↖
//             attr key    list of prefixes to drop, in that order
type InnerParam = Param

pub const name = "attribute_drop_prefixes"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
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