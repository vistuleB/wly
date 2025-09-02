import gleam/option
import gleam/string.{inspect as ins}
import infrastructure.{type Desugarer, Desugarer, type DesugarerTransform, type DesugaringError} as infra
import nodemaps_2_desugarer_transforms as n2t
import vxml.{type VXML, V, type TextLine, TextLine}
import blame as bl

fn nodemap(
  vxml: VXML,
  inner: InnerParam,
) -> VXML {
  case vxml {
    V(_, tag, _, _) if tag == inner.0 -> {
      vxml
      |> infra.v_start_insert_line(inner.1)
      |> infra.v_end_insert_line(inner.2)
    }
    _ -> vxml
  }
}

fn nodemap_factory(inner: InnerParam) -> n2t.OneToOneNoErrorNodeMap {
  nodemap(_, inner)
}

fn transform_factory(inner: InnerParam) -> DesugarerTransform {
  n2t.one_to_one_no_error_nodemap_2_desugarer_transform(nodemap_factory(inner))
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  #(
    param.0,
    TextLine(desugarer_blame(33), param.1.0),
    TextLine(desugarer_blame(34), param.1.1),
  )
  |> Ok
}

type Param = #(String, #(String,    String))
//             ↖         ↖          ↖
//             tag       insert     insert
//                       at start   at end
type InnerParam = #(String, TextLine, TextLine)

pub const name = "insert_line_start_end"
fn desugarer_blame(line_no: Int) {bl.Des([], name, line_no)}

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// inserts text at the beginning and end of a
/// specified tag
pub fn constructor(param: Param) -> Desugarer {
  let assert Ok(inner) = param_to_inner_param(param)
  Desugarer(
    name: name,
    stringified_param: option.Some(ins(inner)),
    stringified_outside: option.None,
    transform: transform_factory(inner),
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
