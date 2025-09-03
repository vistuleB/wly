import gleam/list
import gleam/result
import gleam/option.{Some, None}
import gleam/string.{inspect as ins}
import infrastructure.{type Desugarer, Desugarer, type DesugarerTransform, type DesugaringError, DesugaringError} as infra
import nodemaps_2_desugarer_transforms as n2t
import vxml.{type VXML, Attribute, T, V}
import on

fn ensure_has_id_attribute(
  vxml: VXML, counter: Int
) -> #(VXML, Int, String) {
  let assert V(_, _, _, _) = vxml
  case infra.v_first_attribute_with_key(vxml, "id") {
    Some(attr) -> #(vxml, counter, attr.value)
    None -> {
      let counter = counter + 1
      let id = "_" <> ins(counter) <> "_hgi_"
      let attributes = list.append(
        vxml.attributes,
        [Attribute(vxml.blame, "id", id)]
      )
      #(V(..vxml, attributes: attributes), counter, id)
    }
  }
}

fn nodemap(
  node: VXML,
  counter: Int,
) -> Result(#(VXML, Int), DesugaringError) {
  case node {
    T(_, _) -> Ok(#(node, counter))

    V(_, _, attributes, _) -> {
      let handle_attributes =
        attributes
        |> list.filter(fn(att) { string.starts_with(att.key, "handle")})

      use _, _ <- on.empty_nonempty(
        handle_attributes,
        Ok(#(node, counter)),
      )

      let assert #(
        V(_, _, attributes, _) as node,
        counter,
        id,
      ) = ensure_has_id_attribute(node, counter)

      let assert True = id != ""
      let assert True = id == string.trim(id)

      use attributes <- result.try(
        attributes
        |> list.try_map(
          fn(att) {
            case att.key == "handle" {
              False -> Ok(att)
              True -> {
                use #(handle_name, handle_value) <- result.try(
                    case string.split_once(att.value |> infra.normalize_spaces, " ") {
                    Ok(#(first, second)) -> {
                      case string.contains(first, "|") || string.contains(second, "|") {
                        True -> Error(DesugaringError(att.blame, "handle value contains splitting charachter '|'"))
                        False -> Ok(#(first, second))
                      }
                    }
                    Error(_) -> Ok(#(att.value, ""))
                  }
                )
                Ok(Attribute(..att, value: handle_name <> "|" <> handle_value <> "|" <> id))
              }
            }
          }
        )
      )

      Ok(#(V(..node, attributes: attributes), counter))
    }
  }
}

fn nodemap_factory(_: InnerParam) -> n2t.OneToOneStatefulNodeMap(Int) {
  nodemap
}

fn transform_factory(inner: InnerParam) -> DesugarerTransform {
  n2t.one_to_one_stateful_nodemap_2_desugarer_transform(nodemap_factory(inner), 0)
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(param)
}

type Param = Nil
type InnerParam = Nil

pub const name = "handles_generate_ids"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// For each node that has an attribute of key
/// 'handle':
///
/// 1. generates a unique id attribute added to the
///    node, if not already present
///
/// 2. parses each 'handle' attribute value in the
///    form
/// ```
/// handle=handle_name [handle_value]
/// ```
///    where the handle_value string is an optional
///    string separated from handle_name that may or
///    may not be present, and replaces this key-value
///    pair with
/// ```
/// handle=handle_name|handle_value|id
/// ```
///    while using the empty string for 'handle_value',
///    if not present
pub fn constructor() -> Desugarer {
  Desugarer(
    name: name,
    stringified_param: option.None,
    stringified_outside: option.None,
    transform: case param_to_inner_param(Nil) {
      Error(error) -> fn(_) { Error(error) }
      Ok(inner) -> transform_factory(inner)
    },
  )
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
fn assertive_tests_data() -> List(infra.AssertiveTestDataNoParam) {
  []
}

pub fn assertive_tests() {
  infra.assertive_test_collection_from_data_no_param(name, assertive_tests_data(), constructor)
}
