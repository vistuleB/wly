import gleam/option
import gleam/string.{inspect as ins}
import infrastructure.{type Desugarer, Desugarer, type DesugarerTransform, type DesugaringError } as infra
import nodemaps_2_desugarer_transforms as n2t
import vxml.{type VXML, V}
import blame as bl

fn add_in_list(
  seen_da_tag_yet: Bool,
  upcoming: List(VXML), 
  inner: InnerParam,
) -> List(VXML) {
  case upcoming {
    [] -> []
    [V(_, tag, _, _) as first, ..rest] if tag == inner.0 -> {
      case seen_da_tag_yet {
        True ->
          [inner.1, first, ..add_in_list(True, rest, inner)]
        False ->
          [first, ..add_in_list(True, rest, inner)]
      }
    }
    [first, ..rest] -> [first, ..add_in_list(seen_da_tag_yet, rest, inner)]
  }
}

fn nodemap(
  node: VXML,
  inner: InnerParam,
) -> VXML {
  case node {
    V(_, _, _, children) ->
      V(..node, children: add_in_list(False, children, inner))
    _ -> node
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
  #(
    param.0,
    infra.v_attrs_constructor(desugarer_blame(50), param.1, param.2),
  )
  |> Ok
}

type Param = #(String,         String,          List(#(String, String)))
//             ↖               ↖                ↖
//             insert          tag name         attributes
//             before tags     of new
//             of this name    element
type InnerParam = #(String, VXML)

pub const name = "add_before_but_not_before_first_of_kind"
fn desugarer_blame(line_no: Int) {bl.Des([], name, line_no)}

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// adds a specified tag before each occurrence of
/// some specified other tag, except when the latter
/// tag is occurring for the first time with respect
/// to the current group of siblings
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
