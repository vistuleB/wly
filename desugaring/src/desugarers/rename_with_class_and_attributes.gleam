import gleam/list
import gleam/option
import gleam/string.{inspect as ins}
import infrastructure.{type Desugarer, Desugarer, type DesugarerTransform, type DesugaringError} as infra
import nodemaps_2_desugarer_transforms as n2t
import vxml.{type VXML, V, type Attribute, Attribute}
import blame as bl

fn nodemap(
  vxml: VXML,
  inner: InnerParam,
) -> Result(VXML, DesugaringError) {
  case vxml {
    V(blame, tag, attrs, _) if tag == inner.0 -> {
      let attrs =
        attrs
        |> infra.attributes_append_classes(blame, inner.2)
        |> list.append(inner.3)
      Ok(V(..vxml, tag: inner.1, attributes: attrs))
    }
    _ -> Ok(vxml)
  }
}

fn nodemap_factory(inner: InnerParam) -> n2t.OneToOneNodeMap {
  nodemap(_, inner)
}

fn transform_factory(inner: InnerParam) -> DesugarerTransform {
  n2t.one_to_one_nodemap_2_desugarer_transform(nodemap_factory(inner))
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  let attrs = param.3
  |> list.map(fn(x) { Attribute(desugarer_blame(35), x.0, x.1) })
  Ok(#(param.0, param.1, param.2, attrs))
}

type Param = #(String,   String,   String,  List(#(String, String)))
//             ↖         ↖         ↖        ↖
//             old_tag   new_tag   class    list of attributes 
//                                          as key value pairs
type InnerParam = #(String, String, String, List(Attribute))

pub const name = "rename_with_class_and_attributes"
fn desugarer_blame(line_no: Int) { bl.Des([], name, line_no) }

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// renames tags and adds attributes to them; also 
/// adds a class attribute, that results in editing
/// any existing class attribute, if present
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
