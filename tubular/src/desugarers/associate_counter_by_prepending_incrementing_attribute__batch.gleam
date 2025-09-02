import gleam/dict.{type Dict}
import gleam/list
import gleam/option
import gleam/string
import infrastructure.{type Desugarer, Desugarer, type DesugarerTransform, type DesugaringError, type TrafficLight} as infra
import nodemaps_2_desugarer_transforms as n2t
import vxml.{type VXML, Attribute, T, V}

fn nodemap(
  vxml: VXML,
  inner: InnerParam,
) -> VXML {
  case vxml {
    T(_, _) -> vxml
    V(blame, tag, old_attributes, children) -> {
      case dict.get(inner, tag) {
        Ok(counter_names) -> {
          let #(unassigned_handle_attributes, other_attributes) =
            list.partition(old_attributes, fn(attr) {
              let assert True = attr.value == string.trim(attr.value)
              attr.key == "handle"
              && string.split(attr.value, " ") |> list.length == 1
            })

          let handles_str =
            unassigned_handle_attributes
            |> list.map(fn(attr) { attr.value <> "<<" })
            |> string.join("")

          let new_attributes =
            counter_names
            |> list.index_map(fn(counter_name, index) {
              case index == 0 {
                True ->
                  Attribute(
                    blame,
                    ".",
                    counter_name <> " " <> handles_str <> "::++" <> counter_name,
                  )
                False ->
                  Attribute(
                    blame,
                    ".",
                    counter_name <> " " <> "::++" <> counter_name,
                  )
              }
            })

          V(
            blame,
            tag,
            list.flatten([new_attributes, other_attributes]),
            children,
          )
        }
        Error(Nil) -> vxml
      }
    }
  }
}

fn nodemap_factory(inner: InnerParam) -> n2t.OneToOneNoErrorNodeMap {
  nodemap(_, inner)
}

fn transform_factory(inner: InnerParam) -> DesugarerTransform {
  n2t.one_to_one_no_error_nodemap_2_desugarer_transform(nodemap_factory(inner))
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  let tag_counter_pairs = param |> list.map(fn(triple) { #(triple.0, triple.1) })
  Ok(infra.aggregate_on_first(tag_counter_pairs))
}

type Param = List(#(String, String, TrafficLight))
//                  ↖       ↖        ↖
//                  tag     counter   traffic_light
//                          name

type InnerParam =
  Dict(String, List(String))

pub const name = "associate_counter_by_prepending_incrementing_attribute__batch"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// For each #(tag, counter_name, traffic_light) tuple in the 
/// parameter list, this desugarer adds an
/// attribute of the form
/// ```
/// .=counter_name ::++counter_name
/// ```
/// to each node of tag 'tag', where the key is
/// a period '.' and the value is the string 
/// '<counter_name> ::++<counter_name>'. As 
/// counters are evaluated and substitued also
/// inside of key-value pairs, adding this 
/// key-value pair causes the counter <counter_name>
/// to increment at each occurrence of a node
/// of tag 'tag'. Also assigns unassigned 
/// handles of the attribute list of node 'tag'
/// to the first counter being incremented in
/// this fashion, by this desugarer.
pub fn constructor(
  param: Param,
) -> Desugarer {
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