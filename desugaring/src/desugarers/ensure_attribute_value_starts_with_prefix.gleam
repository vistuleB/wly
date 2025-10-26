import gleam/list
import gleam/option
import gleam/string.{inspect as ins}
import infrastructure.{
  type Desugarer,
  type DesugarerTransform,
  type DesugaringError,
  Desugarer,
} as infra
import nodemaps_2_desugarer_transforms as n2t
import vxml.{
  type Attr,
  type VXML,
  V,
  Attr,
}

fn prefix_suffix_list_acc(
  acc: String,
  chars: List(String),
) -> PrefixesAndSuffixes {
  case chars {
    [] -> [#(acc, "")]
    [first, ..rest] -> {
      let others = prefix_suffix_list_acc(acc <> first, rest)
      [#(acc, chars |> string.join("")), ..others]
    }
  }
}

fn prefix_suffix_list(
  s: String
) -> PrefixesAndSuffixes {
  prefix_suffix_list_acc("", string.split(s, ""))
}

fn add_prefix_of_first_matching_suffix(
  value: String,
  prefixes_suffixes: PrefixesAndSuffixes
) -> String {
  case prefixes_suffixes {
    [] -> panic
    [#(a, b), ..rest] -> case string.starts_with(value, b) {
      True -> a <> value
      False -> add_prefix_of_first_matching_suffix(value, rest)
    }
  }
}

fn update_attr(
  attr: Attr,
  inner: InnerParam,
) -> Attr {
  case inner.0 == attr.key {
    True -> Attr(..attr, val: add_prefix_of_first_matching_suffix(attr.val, inner.1))
    _ -> attr
  }
}

fn nodemap(
  vxml: VXML,
  inner: InnerParam,
) -> VXML {
  case vxml {
    V(_, _, attrs, _) -> V(..vxml, attrs: list.map(attrs, update_attr(_, inner)))
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
  Ok(#(param.0, echo prefix_suffix_list(param.1)))
}

type PrefixesAndSuffixes = List(#(String, String))

type Param = #(String,         String)
//             ↖               ↖
//             attr key        thing should start with
type InnerParam = #(String, PrefixesAndSuffixes)

pub const name = "ensure_attribute_value_starts_with_prefix"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// Used for changing the value of an attr.
/// Takes an attr key and a replacement string 
/// in which "()" is used as a stand-in for the 
/// current value. For example, replacing attr 
/// value "images/img.png" with the replacement 
/// string "/()" will result in the new attr 
/// value "/images/img.png"
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