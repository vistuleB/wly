import gleam/dict.{type Dict}
import gleam/list
import gleam/option
import infrastructure.{type Desugarer, Desugarer, type DesugarerTransform, type DesugaringError} as infra
import nodemaps_2_desugarer_transforms as n2t
import vxml.{type VXML, T, V}
import on

fn nodemap(
  vxml: VXML,
  inner: InnerParam,
) -> VXML {
  case vxml {
    T(_, _) -> vxml
    V(blame, tag, attrs, children) -> {

      use inner_dict <- on.error_ok(
        dict.get(inner, tag),
        fn(_) { vxml },
      )

      let new_children =
        list.map(children, fn(child) {
          use child_blame, child_tag, child_attrs, grandchildren <- infra.on_t_on_v(child, fn(_, _){
            child
          })
          case dict.get(inner_dict, child_tag) {
            Error(Nil) -> child
            Ok(new_name) -> V(child_blame, new_name, child_attrs, grandchildren)
          }
        })

      V(blame, tag, attrs, new_children)
    }
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
  list.fold(
    param,
    dict.from_list([]),
    fn(
      acc: Dict(String, Dict(String, String)),
      incoming: #(String, String, String),
    ) {
      let #(old_name, new_name, parent_name) = incoming
      case dict.get(acc, parent_name) {
        Error(Nil) -> {
          dict.insert(
            acc,
            parent_name,
            dict.from_list([#(old_name, new_name)]),
          )
        }
        Ok(existing_dict) -> {
          dict.insert(
            acc,
            parent_name,
            dict.insert(existing_dict, old_name, new_name),
          )
        }
      }
    }
  )
  |> Ok
}

type Param = List(#(String,    String,    String))
//                  ↖          ↖          ↖
//                  old_name   new_name   parent
type InnerParam = Dict(String, Dict(String, String))

pub const name = "rename_if_child_of__batch"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// renames tags when they appear as children of a
/// specified parent tag
pub fn constructor(param: Param) -> Desugarer {
  Desugarer(
    name: name,
    stringified_param: option.Some(param |> infra.list_param_stringifier),
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
