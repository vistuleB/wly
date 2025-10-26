import gleam/option
import gleam/string.{inspect as ins}
import infrastructure.{
  type Desugarer,
  type DesugarerTransform,
  type DesugaringError,
  type TrafficLight,
  Desugarer,
  Continue,
} as infra
import nodemaps_2_desugarer_transforms as n2t
import vxml.{
  type VXML,
  type Attr,
  Attr,
  V,
}
import blame as bl

fn nodemap(
  vxml: VXML,
  inner: InnerParam,
) -> #(VXML, TrafficLight) {
  case vxml {
    V(_, tag, attrs, _) if tag == inner.0 -> 
      #(V(..vxml, attrs: [inner.1, ..attrs]), inner.2)
    _ -> #(vxml, Continue)
  }
}

fn nodemap_factory(inner: InnerParam) -> n2t.EarlyReturnOneToOneNoErrorNodeMap {
  nodemap(_, inner)
}

fn transform_factory(inner: InnerParam, outside: List(String)) -> DesugarerTransform {
  nodemap_factory(inner)
  |> n2t.early_return_one_to_one_no_error_nodemap_2_desugarer_transform_with_forbidden(outside)
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  #(
    param.0, 
    Attr(desugarer_blame(43), "_", param.1 <> " ::++" <> param.1),
    param.2,
  )
  |> Ok
}

type Param = #(String, String,  TrafficLight)
//             ↖       ↖        ↖
//             tag     counter  pursue-nested-or-not
type InnerParam = #(String, Attr, TrafficLight)
fn desugarer_blame(line_no: Int) { bl.Des([], name, line_no) }

pub const name = "prepend_counter_incrementing_attribute__outside"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// For each #(tag, counter_name, traffic_light) 
/// tuple in the parameter list, this desugarer adds 
/// an attr of the form
/// ```
/// .=counter_name ::++counter_name
/// ```
/// to each node of tag 'tag', where the key is a 
/// period '.' and the value is the string 
/// '<counter_name> ::++<counter_name>'. As counters
/// are evaluated and substitued also inside of 
/// key-value pairs, adding this key-value pair 
/// causes the counter <counter_name> to increment at
/// each occurrence of a node of tag 'tag'.
pub fn constructor(
  param: Param,
  outside: List(String),
) -> Desugarer {
  Desugarer(
    name: name,
    stringified_param: option.Some(ins(param)),
    stringified_outside: option.None,
    transform: case param_to_inner_param(param) {
      Error(error) -> fn(_) { Error(error) }
      Ok(inner) -> transform_factory(inner, outside)
    },
  )
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
fn assertive_tests_data() -> List(infra.AssertiveTestDataWithOutside(Param)) {
  []
}

pub fn assertive_tests() {
  infra.assertive_test_collection_from_data_with_outside(name, assertive_tests_data(), constructor)
}
