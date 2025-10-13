import blame as bl
import gleam/list
import gleam/option
import gleam/result
import gleam/string.{inspect as ins}
import infrastructure.{type Desugarer, Desugarer, type DesugarerTransform, type DesugaringError, DesugaringError} as infra
import nodemaps_2_desugarer_transforms as n2t
import vxml.{type Attr, Attr, type VXML, T, V}

fn lookup_attrs_by_key(
  in: List(Attr),
  key: String,
) -> Result(#(Attr, List(Attr)), Nil) {
  let #(matches, non_matches) = list.partition(in, fn(b) { b.key == key })
  let assert True = list.length(matches) <= 1
  case matches {
    [] -> Error(Nil)
    [unique] -> Ok(#(unique, non_matches))
    _ -> panic as "more than one match"
  }
}

fn maybe_semicolon(thing: String) -> String {
  case string.ends_with(thing, ";") {
    True -> ""
    False -> ";"
  }
}

fn merge_one_attr(
  attrs: List(Attr),
  to_merge: Attr,
) -> Result(List(Attr), DesugaringError) {
  let Attr(blame, key, value) = to_merge
  let res = lookup_attrs_by_key(attrs, key)
  case res {
    Error(Nil) -> Ok([to_merge, ..attrs])
    Ok(#(existing, remaining)) -> {
      case key == "style" {
        False ->
          Error(DesugaringError(
            existing.blame,
            "attr of key '"
              <> key
              <> "' already exists in child (value '"
              <> value
              <> "' in parent)",
          ))
        True ->
          Ok([
            Attr(
              existing.blame |> bl.append_comment(blame |> ins),
              "style",
              existing.value <> maybe_semicolon(existing.value) <> value,
            ),
            ..remaining
          ])
      }
    }
  }
}

fn merge_attrs(
  attrs1: List(Attr),
  attrs2: List(Attr),
) -> Result(List(Attr), DesugaringError) {
  list.fold(attrs1, Ok(attrs2), fn(attrs, attr) {
    case attrs {
      Error(e) -> Error(e)
      Ok(attrs) -> merge_one_attr(attrs, attr)
    }
  })
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
  List(#(String, String))
//       ↖       ↖
//       parent  child

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
