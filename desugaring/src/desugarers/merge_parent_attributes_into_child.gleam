import gleam/list
import gleam/option.{Some, None}
import gleam/result
import gleam/string.{inspect as ins}
import infrastructure.{
  type DesugarerTransform,
  type DesugaringError,
  type Desugarer,
  DesugaringError,
  Desugarer,
} as infra
import nodemaps_2_desugarer_transforms as n2t
import vxml.{
  type Attr,
  type VXML,
  T,
  V,
}

fn merge_one_attr(
  attrs: List(Attr),
  to_merge: Attr,
) -> Result(List(Attr), DesugaringError) {
  case to_merge.key {
    "style" -> Ok(infra.attrs_merge_styles(attrs, to_merge.blame, to_merge.val))
    "class" -> Ok(infra.attrs_append_classes(attrs, to_merge.blame, to_merge.val))
    key -> case infra.attrs_val_of_first_with_key(attrs, key) {
      Some(child_val) -> Error(DesugaringError(
        to_merge.blame,
        "attr of key '"
        <> key
        <> "' already exists in child (value '"
        <> to_merge.val
        <> "' in parent, '"
        <> child_val
        <> "' in child)",
      ))
      None -> Ok([to_merge, ..attrs])
    }
  }
}

fn merge_attrs(
  from: List(Attr),
  onto: List(Attr),
) -> Result(List(Attr), DesugaringError) {
  list.try_fold(
    from,
    onto,
    merge_one_attr
  )
}

fn nodemap(
  vxml: VXML,
  inner: InnerParam,
) -> Result(VXML, DesugaringError) {
  case vxml {
    T(_, _) -> Ok(vxml)
    V(blame, tag, attrs, children) -> {
      case
        result.all(
          list.map(children, fn(child) {
            case child {
              T(_, _) -> Ok(child)
              V(child_blame, child_tag, child_attrs, grandchildren) -> {
                case list.contains(inner, #(tag, child_tag)) {
                  False -> Ok(child)
                  True -> {
                    case merge_attrs(attrs, child_attrs) {
                      Ok(child_attrs) ->
                        Ok(V(child_blame, child_tag, child_attrs, grandchildren))
                      Error(d) -> Error(d)
                    }
                  }
                }
              }
            }
          }),
        )
      {
        Ok(new_children) -> Ok(V(blame, tag, attrs, new_children))
        Error(e) -> Error(e)
      }
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

type Param = List(#(String, String))
//                  ↖       ↖
//                  parent  child

type InnerParam = Param

pub const name = "merge_parent_attributes_into_child"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// merges parent attrs into child elements for
/// specified parent-child tag pairs
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
