import gleam/option.{type Option, None, Some}
import gleam/list
import vxml.{type VXML, V, T}
import infrastructure.{type Desugarer, Desugarer, type DesugarerTransform, type DesugaringError} as infra
import nodemaps_2_desugarer_transforms as n2t
import blame

fn process_children(
  already_processed: List(VXML),
  previous_sibling: Option(VXML),
  upcoming: List(VXML),
  condition: fn(Option(VXML), VXML, Option(VXML)) -> #(Bool, Bool),
  bef: VXML,
  aft: VXML,
) -> List(VXML) {
  case upcoming {
    [] -> list.reverse(already_processed)
    [child, ..rest] -> {
      let next_sibling = list.first(rest) |> option.from_result
      let #(do_bef, do_aft) = condition(previous_sibling, child, next_sibling)

      let acc = already_processed
      let acc = case do_bef {
        True -> [bef, ..acc]
        False -> acc
      }
      let acc = [child, ..acc]

      let #(new_acc, new_prev) = case do_aft {
        True -> #([aft, ..acc], Some(aft))
        False -> #(acc, Some(child))
      }

      process_children(new_acc, new_prev, rest, condition, bef, aft)
    }
  }
}

fn nodemap(vxml: VXML, param: Param) -> VXML {
  case vxml {
    V(blame, tag, attrs, children) -> {
      let processed_children =
        process_children([], None, children, param.0, param.1, param.2)
      V(blame, tag, attrs, processed_children)
    }
    _ -> vxml
  }
}

fn nodemap_factory(param: Param) -> n2t.OneToOneNoErrorNodemap {
  nodemap(_, param)
}

fn transform_factory(param: Param) -> DesugarerTransform {
  nodemap_factory(param)
  |> n2t.one_to_one_no_error_nodemap_2_desugarer_transform()
}

fn param_to_inner_param(param: Param) -> Result(Param, DesugaringError) {
  Ok(param)
}

pub type Param =
  #(
    fn(Option(VXML), VXML, Option(VXML)) -> #(Bool, Bool),
    VXML,
    VXML,
  )

pub const name = "insert_before_after_if"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// traverses children and inserts nodes before or
/// after based on a ternary condition
pub fn constructor(param: Param) -> Desugarer {
  Desugarer(
    name: name,
    stringified_param: Some("insert_before_after_if_param"),
    stringified_outside: None,
    transform: case param_to_inner_param(param) {
      Error(error) -> fn(_) { Error(error) }
      Ok(inner) -> transform_factory(inner)
    },
  )
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊_test_collection_from_data
fn assertive_tests_data() -> List(infra.AssertiveTestData(Param)) {
  let b = blame.Des([], name, 0)
  let bef = T(b, [vxml.Line(b, "[")])
  let aft = T(b, [vxml.Line(b, "]")])

  let cond = fn(_prev, child, _next) {
    case child {
      V(_, "wrap", _, _) -> #(True, True)
      _ -> #(False, False)
    }
  }

  let param = #(cond, bef, aft)

  [
    infra.AssertiveTestData(
      param: param,
      source: "
              <> div
                <> wrap
              ",
      expected: "
                <> div
                  <>
                    '['
                  <> wrap
                  <>
                    ']'
                ",
    ),
    infra.AssertiveTestData(
      param: param,
      source: "
              <> div
                <> span
                <> wrap
                <> span
              ",
      expected: "
                <> div
                  <> span
                  <>
                    '['
                  <> wrap
                  <>
                    ']'
                  <> span
                ",
    ),
  ]
}

pub fn assertive_tests() {
  infra.assertive_test_collection_from_data(name, assertive_tests_data(), constructor)
}
