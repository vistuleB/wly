import gleam/list
import gleam/option
import gleam/string.{inspect as ins}
import infrastructure.{type Desugarer, Desugarer, type DesugarerTransform, type DesugaringError} as infra
import nodemaps_2_desugarer_transforms as n2t
import vxml.{type VXML, Attribute, V}
import blame as bl

fn child_mapper(
  vxml: VXML,
  inner: InnerParam
) -> VXML {
  case vxml {
    V(_, child_tag, attributes, _) if child_tag == inner.0 -> {
      let old_keys = infra.keys(attributes)
      let attributes =
        case list.contains(old_keys, inner.2) {
          True -> attributes
          False -> list.append(
            attributes,
            [Attribute(desugarer_blame(21), inner.2, inner.3)],
          )
        }
      V(..vxml, attributes: attributes)
    }
    _ -> vxml
  }
}

fn nodemap(
  vxml: VXML,
  inner: InnerParam,
) -> VXML {
  case vxml {
    V(_, parent_tag, _, children) if parent_tag == inner.1 -> {
      let children = list.map(children, child_mapper(_, inner))
      V(..vxml, children: children)
    }
    _ -> vxml
  }
}

fn nodemap_factory(inner: InnerParam) -> n2t.OneToOneNoErrorNodeMap {
  nodemap(_, inner)
}

fn transform_factory(inner: InnerParam) -> DesugarerTransform {
  nodemap_factory(inner)
  |> n2t.one_to_one_no_error_nodemap_2_desugarer_transform()
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(param)
}

type Param = #(String, String, String, String)
//             ↖       ↖       ↖       ↖
//             tag     parent  key     value
type InnerParam = Param

pub const name = "append_attribute_if_child_of"
fn desugarer_blame(line_no: Int) {bl.Des([], name, line_no)}

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// adds an attribute-pair to a tag when it is the 
/// child of another specified tag; will not 
/// overwrite if attribute with that key already
/// exists
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
  [
    infra.AssertiveTestData(
      param: #("B", "parent", "key1", "val1"),
      source:   "
                <> root
                  <> B
                    <> parent
                  <> parent
                    <> B
                  <> parent
                    <> B
                      key1=val2
                ",
      expected: "
                <> root
                  <> B
                    <> parent
                  <> parent
                    <> B
                      key1=val1
                  <> parent
                    <> B
                      key1=val2
                "
    )
  ]
}

pub fn assertive_tests() {
  infra.assertive_test_collection_from_data(name, assertive_tests_data(), constructor)
}
