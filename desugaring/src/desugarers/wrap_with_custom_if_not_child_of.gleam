import gleam/option
import gleam/list
import gleam/string.{inspect as ins}
import infrastructure.{
  type Desugarer,
  type DesugarerTransform,
  type DesugaringError,
  Desugarer,
  DesugaringError,
} as infra
import nodemaps_2_desugarer_transforms as n2t
import vxml.{type VXML, V, T}
import blame as bl

fn child_map(
  vxml: VXML,
  inner: InnerParam,
) -> VXML {
  case vxml {
    V(_, tag, _, _) if tag == inner.0 -> {
      let z = inner.1
      let assert V(_, _, _, _) = z // gleam not mature enough to just use inner.1 here...
      V(..z, children: [vxml])
    }
    _ -> vxml
  }
}

fn nodemap(
  vxml: VXML,
  inner: InnerParam,
) -> VXML {
  case vxml {
    V(_, tag, _, children) -> {
      case list.contains(inner.2, tag) {
        True -> vxml
        False -> {
          let children = list.map(children, child_map(_, inner))
          V(..vxml, children: children)
        }
      }
    }
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
  case param.1 {
    T(..) -> Error(DesugaringError(desugarer_blame(58), "expecting V-node as wrapper"))
    V(_, _, _, []) -> Ok(param)
    _ -> Error(DesugaringError(desugarer_blame(60), "wrapper V-node is not childless"))
  }
}

type Param = #(String,   VXML,       List(String))
//             ↖         ↖           ↖               
//             tag to    thing to    ...if not child of
//             wrap      wrap with   any of these  
type InnerParam = Param

pub const name = "wrap_with_custom_if_not_child_of"
fn desugarer_blame(line_no: Int) { bl.Des([], name, line_no) }

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// wrap
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
