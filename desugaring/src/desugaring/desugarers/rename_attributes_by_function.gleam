import gleam/list
import gleam/option
import desugaring/core.{type Desugarer, Desugarer, type DesugarerTransform, type DesugaringError} as core
import desugaring/nodemaps_2_transform as n2t
import vxml.{type VXML, T, V, type Attr, Attr}

fn rename_attr_key(attr: Attr, transform_fn: fn(String) -> String) -> Attr {
  Attr(..attr, key: transform_fn(attr.key))
}

fn nodemap(
  vxml: VXML,
  inner: InnerParam,
) -> Result(VXML, DesugaringError) {
  case vxml {
    T(_, _) -> Ok(vxml)
    V(_, _, attrs, _) -> {
      Ok(V(..vxml, attrs: list.map(attrs, rename_attr_key(_, inner))))
    }
  }
}

fn nodemap_factory(inner: InnerParam) -> n2t.OneToOneNodemap {
  nodemap(_, inner)
}

fn transform_factory(inner: InnerParam) -> DesugarerTransform {
  n2t.one_to_one_nodemap_2_desugarer_transform(nodemap_factory(inner))
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(param)
}

type Param =
  fn(String) -> String

type InnerParam = Param

pub const name = "rename_attributes_by_function"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// renames attr keys using a provided
/// transformation function
pub fn constructor(param: Param) -> Desugarer {
  Desugarer(
    name: name,
    stringified_param: option.None,
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
  [
    core.AssertiveTestData(
      param: core.kebab_case_to_camel_case,
      source:   "
                <> div
                  data-test=value1
                  my-attr=value2
                  another-long-name=value3
                ",
      expected: "
                <> div
                  dataTest=value1
                  myAttr=value2
                  anotherLongName=value3
                "
    )
  ]
}

pub fn assertive_tests() {
  core.assertive_test_collection_from_data(name, assertive_tests_data(), constructor)
}
