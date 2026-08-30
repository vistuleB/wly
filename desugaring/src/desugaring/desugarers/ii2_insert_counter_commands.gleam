import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
}
import desugaring/nodemaps_2_transform as n2t
import gleam/list
import gleam/option.{type Option}
import gleam/string
import on
import vxml.{type Line, type VXML, Line, T, V}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(InnerParam(
    counter_command: param.0,
    target_key_value: param.1,
    before_strings: param.2,
    wrapper_tag: param.3,
  ))
}

fn inner_param_to_transform(inner: InnerParam) -> DesugarerTransform {
  let nodemap: n2t.OneToOneNodemap = nodemap(_, inner)
  n2t.one_to_one_nodemap_2_desugarer_transform(nodemap)
}

fn nodemap(vxml: VXML, inner: InnerParam) -> Result(VXML, DesugaringError) {
  let #(key, value) = inner.target_key_value

  case vxml {
    T(_, _) -> Ok(vxml)
    V(_, _, _, children) -> {
      use <- on.false_true(core.v_has_key_val(vxml, key, value), on_false: fn() {
        Ok(vxml)
      })

      case children {
        [T(t_blame, lines), ..] -> {
          let assert [first_line, ..] = lines
          let found_prefix =
            list.find(inner.before_strings, fn(prefix) {
              string.starts_with(first_line.content, prefix)
            })

          case found_prefix, list.is_empty(inner.before_strings) {
            Ok(found_prefix), _ -> {
              let blamed_cc = Line(first_line.blame, inner.counter_command)
              let blamed_prefix = Line(first_line.blame, found_prefix)
              let rest =
                Line(
                  first_line.blame,
                  string.length(found_prefix)
                    |> string.drop_start(first_line.content, _),
                )

              updated_node(
                vxml,
                option.Some(blamed_prefix),
                #(blamed_cc, inner.wrapper_tag),
                rest,
              )
              |> Ok
            }
            Error(_), True -> {
              let blamed_cc = Line(t_blame, inner.counter_command)
              updated_node(
                vxml,
                option.None,
                #(blamed_cc, inner.wrapper_tag),
                first_line,
              )
              |> Ok
            }
            Error(_), False -> Ok(vxml)
          }
        }
        _ -> Ok(vxml)
      }
    }
  }
}

fn updated_node(
  vxml: VXML,
  prefix: Option(Line),
  cc: #(Line, Option(String)),
  rest: Line,
) -> VXML {
  let assert V(blame, tag, attrs, children) = vxml
  let assert [T(t_blame, lines), ..] = children

  let prefix = on.eager_none_some(prefix, [], fn(p) { [p] })

  let #(counter_command, wrapper) = cc

  let new_children =
    on.none_some(
      wrapper,
      fn() {
        [
          T(
            t_blame,
            list.flatten([
              prefix,
              [counter_command],
              [rest],
              list.drop(lines, 1),
            ]),
          ),
          ..list.drop(children, 1)
        ]
      },
      fn(wrapper) {
        let wrapper_node =
          V(t_blame, wrapper, [], [T(t_blame, [counter_command])])
        [
          T(t_blame, prefix),
          wrapper_node,
          T(t_blame, [rest, ..list.drop(lines, 1)]),
          ..list.drop(children, 1)
        ]
      },
    )

  V(blame, tag, attrs, new_children)
}

type Param =
  #(
    // Counter command to insert.
    String,
    // Attribute key and value selecting target elements.
    #(String, String),
    // Strings before which to insert the command.
    List(String),
    // Optional element name wrapping the command.
    Option(String),
  )

type InnerParam {
  InnerParam(
    counter_command: String,
    target_key_value: #(String, String),
    before_strings: List(String),
    wrapper_tag: Option(String),
  )
}

pub const name = "ii2_insert_counter_commands"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
/// inserts TI2 counter commands into text nodes of
/// specified elements
/// # Param:
///  - Counter command to insert . ex: "::++Counter"
///  - key-value pair of node to insert counter
///    command
///  - list of strings before counter command
///  - A wrapper tag to wrap the counter command
///    string
pub fn constructor(param: Param) -> Desugarer {
  authoring.desugarer(
    name: name,
    param: param,
    prepare: param_to_inner_param,
    transform: inner_param_to_transform,
  )
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
fn assertive_tests_data() -> List(core.AssertiveTestData(Param)) {
  []
}

pub fn assertive_tests() {
  core.assertive_test_collection_from_data(
    name,
    assertive_tests_data(),
    constructor,
  )
}
