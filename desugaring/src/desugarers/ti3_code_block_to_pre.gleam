import gleam/option.{Some, None}
import gleam/string.{inspect as ins}
import gleam/int
import gleam/list
import infrastructure.{type Desugarer, Desugarer, type DesugarerTransform, type DesugaringError, DesugaringError} as infra
import nodemaps_2_desugarer_transforms as n2t
import vxml.{type VXML, V}
import blame as bl
import on

fn nodemap(
  vxml: VXML,
) -> Result(VXML, DesugaringError) {
  case vxml {
    V(_, "CodeBlock", _, _) -> {
      use language <- on.lazy_none_some(
        infra.v_value_of_first_attribute_with_key(vxml, "language"),
        fn() { Ok(V(..vxml, tag: "pre")) },
      )

      use #(language, listing, line_no) <- on.ok(
        case string.split_once(language, "listing") {
          Ok(#(before, after)) -> {
            let language = case string.ends_with(before, "-") {
              True -> string.drop_end(before, 1)
              False -> string.drop_end(before, 0)
            }

            use line_no <- on.ok(
              case string.split_once(after, "@") {
                Ok(#("", after)) -> {
                  case int.parse(after) {
                    Ok(line_no) -> Ok(Some(ins(line_no - 1)))
                    _ -> Error(DesugaringError(vxml.blame, "cannot parse '@' line number as integer: " <> after))
                  }
                }
                _ -> Ok(None)
              }
            )

            Ok(#(language, True, line_no))
          }
          
          _ -> Ok(#(language, False, None))
        }
      )

      let class = case listing {
        True -> [vxml.Attribute(desugarer_blame(49), "class", "listing")]
        False -> []
      }
      
      let style = case line_no {
        Some(line_no) -> [vxml.Attribute(desugarer_blame(54), "style", "counter-set:listing " <> line_no)]
        None -> []
      }

      let language = [vxml.Attribute(desugarer_blame(58), "language", language)]
      
      V(
        ..vxml,
        tag: "pre",
        attributes: [
          class,
          style,
          language
        ] |> list.flatten
      )
      |> Ok
    }
    _ -> Ok(vxml)
  }
}

fn nodemap_factory(_inner: InnerParam) -> n2t.OneToOneNodeMap {
  nodemap
}

fn transform_factory(inner: InnerParam) -> DesugarerTransform {
  nodemap_factory(inner)
  |> n2t.one_to_one_nodemap_2_desugarer_transform
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(param)
}

pub const name = "ti3_code_block_to_pre"
fn desugarer_blame(line_no: Int) -> bl.Blame { bl.Des([], name, line_no) }

type Param = Nil
type InnerParam = Param

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// ...
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
