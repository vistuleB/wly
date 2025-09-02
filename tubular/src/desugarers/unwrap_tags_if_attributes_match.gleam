import gleam/list
import gleam/option
import gleam/pair
import gleam/string.{inspect as ins}
import infrastructure.{type Desugarer, Desugarer, type DesugarerTransform, type DesugaringError} as infra
import nodemaps_2_desugarer_transforms as n2t
import vxml.{type Attribute, type VXML, T, V}

fn matches_all_key_value_pairs(
  attrs: List(Attribute),
  key_value_pairs: List(#(String, String)),
) -> Bool {
  list.all(key_value_pairs, fn(key_value) {
    let #(key, value) = key_value
    list.any(attrs, fn(attr) { attr.key == key && attr.value == value })
  })
}

fn nodemap(
  node: VXML,
  inner: InnerParam,
) -> Result(List(VXML), DesugaringError) {
  case node {
    T(_, _) -> Ok([node])
    V(_, tag, attrs, children) -> {
      case list.find(inner, fn(pair) { pair |> pair.first == tag }) {
        Error(Nil) -> Ok([node])
        Ok(#(_, attrs_to_match)) -> {
          case matches_all_key_value_pairs(attrs, attrs_to_match) {
            False -> Ok([node])
            True -> Ok(children)
            // bye-bye
          }
        }
      }
    }
  }
}

fn nodemap_factory(inner: InnerParam) -> n2t.OneToManyNodeMap {
  nodemap(_, inner)
}

fn transform_factory(inner: InnerParam) -> DesugarerTransform {
  n2t.one_to_many_nodemap_2_desugarer_transform(nodemap_factory(inner))
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(param)
}

type Param = List(#(String, List(#(String, String))))
//              ↖       ↖
//              tag     attributes to match

type InnerParam = Param

pub const name = "unwrap_tags_if_attributes_match"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// unwraps tags if all specified attributes match
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
