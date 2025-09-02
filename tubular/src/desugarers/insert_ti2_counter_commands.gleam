import gleam/list
import gleam/option.{type Option}
import gleam/string.{inspect as ins}
import infrastructure.{type Desugarer, Desugarer, type DesugarerTransform, type DesugaringError} as infra
import nodemaps_2_desugarer_transforms as n2t
import vxml.{type TextLine, type VXML, TextLine, T, V}
import on

fn updated_node(
  vxml: VXML,
  prefix: Option(TextLine),
  cc: #(TextLine, Option(String)),
  // string is for the wrapper tag
  rest: TextLine,
) -> VXML {
  let assert V(blame, tag, attributes, children) = vxml
  let assert [T(t_blame, lines), ..] = children

  let prefix = on.none_some(prefix, [], fn(p) { [p] })

  let #(counter_command, wrapper) = cc

  let new_children =
    on.none_some(
      wrapper,
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
      ],
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

  V(blame, tag, attributes, new_children)
}

fn nodemap(
  vxml: VXML,
  inner: InnerParam,
) -> Result(VXML, DesugaringError) {
  let #(counter_command, #(key, value), prefixes, wrapper) = inner

  case vxml {
    T(_, _) -> Ok(vxml)
    V(_, _, _, children) -> {
      use <- on.false_true(
        infra.v_has_key_value(vxml, key, value),
        on_false: Ok(vxml),
      )

      // get first text node
      case children {
        [T(t_blame, lines), ..] -> {
          let assert [first_line, ..] = lines
          let found_prefix =
            list.find(prefixes, fn(prefix) {
              string.starts_with(first_line.content, prefix)
            })

          case found_prefix, list.is_empty(prefixes) {
            Ok(found_prefix), _ -> {
              let blamed_cc = TextLine(first_line.blame, counter_command)
              let blamed_prefix = TextLine(first_line.blame, found_prefix)
              let rest =
                TextLine(
                  first_line.blame,
                  string.length(found_prefix)
                    |> string.drop_start(first_line.content, _),
                )

              updated_node(
                vxml,
                option.Some(blamed_prefix),
                #(blamed_cc, wrapper),
                rest,
              )
              |> Ok
            }
            Error(_), True -> {
              let blamed_cc = TextLine(t_blame, counter_command)
              updated_node(vxml, option.None, #(blamed_cc, wrapper), first_line) |> Ok
            }
            Error(_), False -> Ok(vxml)
          }
        }
        _ -> Ok(vxml)
      }
    }
  }
}

fn nodemap_factory(inner: InnerParam) -> n2t.OneToOneNodeMap {
  nodemap(_, inner)
}

fn transform_factory(inner: InnerParam) -> DesugarerTransform {
  n2t.one_to_one_nodemap_2_desugarer_transform(nodemap_factory(inner))
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(param)
}

type Param =
  #(String, #(String, String), List(String), Option(String))
//  ↖       ↖                  ↖            ↖
//  counter key-value pair     list of      wrapper
//  command to insert         strings      tag to
//  to      counter command   before       wrap the
//  insert                    counter      counter
//                           command      command

type InnerParam = Param

pub const name = "insert_ti2_counter_commands"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
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
