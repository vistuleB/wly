import gleam/string
import gleam/list
import gleam/option
import infrastructure.{type Desugarer, Desugarer, type DesugarerTransform, type DesugaringError} as infra
import nodemaps_2_desugarer_transforms as n2t
import vxml.{type VXML, V, T}

fn remaining_properly_tokenized(
  in_text_mode: Bool,
  remaining: List(VXML),
) -> Bool {
  case remaining {
    [] -> !in_text_mode
    [T(_, _), ..] -> False
    [V(_, "__StartTokenizedT", _, _), ..rest] -> case in_text_mode {
      True -> False
      False -> remaining_properly_tokenized(True, rest)
    }
    [V(_, "__EndTokenizedT", _, _), ..rest] -> case in_text_mode {
      False -> False
      True -> remaining_properly_tokenized(False, rest)
    }
    [_, ..rest] -> remaining_properly_tokenized(in_text_mode, rest)
  }
}

fn has_href(vxml: VXML) -> Bool {
  infra.v_has_attribute_with_key(vxml, "href")
}

fn is_v_and_has_href(vxml: VXML) -> Bool {
  infra.is_v_and_has_attribute_with_key(vxml, "href")
}

fn is_v_and_has_tag_starting_with(
  vxml: VXML,
  prefix: String,
) -> Bool {
  case vxml {
    T(_, _) -> False
    V(_, tag, _, _) -> string.starts_with(tag, prefix)
  }
}

fn nodemap(
  vxml: VXML,
) -> Result(VXML, DesugaringError) {
  case vxml {
    T(_, _) -> Ok(vxml)
    V(_, _, attrs, children) -> {
      case has_href(vxml), list.any(children, is_v_and_has_href) {
        False, False -> {
          case list.any(children, is_v_and_has_tag_starting_with(_, "__")) {
            True -> Error(infra.DesugaringError(vxml.blame, "found tokenization error (1)"))
            False -> Ok(vxml)
          }
        }
        False, True -> {
          case remaining_properly_tokenized(False, children), infra.attributes_have_key(attrs, "had_href_child") {
            True, True -> Ok(vxml)
            False, True -> Error(infra.DesugaringError(vxml.blame, "found tokenization error (2a)"))
            True, False -> Error(infra.DesugaringError(vxml.blame, "found tokenization error (2b)"))
            False, False -> Error(infra.DesugaringError(vxml.blame, "found tokenization error (2c)"))
          }
        }
        True, False -> {
          case remaining_properly_tokenized(False, children) {
            True -> Ok(vxml)
            False -> Error(infra.DesugaringError(vxml.blame, "found tokenization error (3)"))
          }
        }
        True, True -> panic as "not expecting an href within an href"
      }
    }
    
  }
}

fn nodemap_factory(_: InnerParam) -> n2t.OneToOneNodeMap {
  nodemap
}

fn transform_factory(inner: InnerParam) -> DesugarerTransform {
  nodemap_factory(inner)
  |> n2t.one_to_one_nodemap_2_desugarer_transform()
}

fn param_to_inner_param() -> Result(InnerParam, DesugaringError) {
  Ok(Nil)
}

type Param = Nil
type InnerParam = Param

pub const name = "check_proper_href_tokenization"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// 
pub fn constructor() -> Desugarer {
  Desugarer(
    name: name,
    stringified_param: option.None,
    stringified_outside: option.None,
    transform: case param_to_inner_param() {
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