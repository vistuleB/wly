import gleam/int
import gleam/list
import gleam/option
import gleam/string.{inspect as ins}
import infrastructure.{type Desugarer, Desugarer, type DesugarerTransform, type DesugaringError} as infra
import nodemaps_2_desugarer_transforms as n2t
import vxml.{type Attr, Attr, type VXML, T, V}

fn update_attrs(
  tag: String,
  attrs: List(Attr),
  inner: InnerParam,
) -> List(Attr) {
  list.fold(
    over: inner,
    from: attrs,
    with: fn(
      current_attrs: List(Attr),
      tag_attr_name_pair: #(String, String),
    ) -> List(Attr) {
      let #(tag_name, attr_name) = tag_attr_name_pair
      case tag_name == "" || tag_name == tag {
        False -> current_attrs
        True -> {
          list.map(
            current_attrs,
            fn(attr: Attr) -> Attr {
              let Attr(blame, key, value) = attr
              case attr_name == "" || attr_name == key {
                False -> attr
                True -> {
                  case int.parse(value) {
                    Error(_) -> attr
                    Ok(z) ->
                      Attr(blame, key, int.to_string(z) <> ".0")
                  }
                }
              }
            },
          )
        }
      }
    },
  )
}

fn nodemap(
  node: VXML,
  inner: InnerParam,
) -> Result(VXML, DesugaringError) {
  case node {
    T(_, _) -> Ok(node)
    V(blame, tag, attrs, children) -> {
      Ok(V(blame, tag, update_attrs(tag, attrs, inner), children))
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

type Param =
  List(#(String,              String))
//       ↖                    ↖
//       tag name,            attr name,
//       matches all          matches all attrs
//       tag if set to ""     if set to ""

type InnerParam = Param

pub const name = "convert_int_attributes_to_float"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// converts int to float for all attrs keys
/// that match one of the entries in 'param', per
/// the matching rules above
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