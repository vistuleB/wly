import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string.{inspect as ins}
import infrastructure.{
  type Desugarer,
  type DesugarerTransform,
  type DesugaringError,
  Desugarer,
} as infra
import nodemaps_2_desugarer_transforms as n2t
import vxml.{type VXML, T, V}
import blame as bl

fn accumulator(
  inner: String,
  already_processed: List(VXML),
  last_dude: Option(VXML),
  whitespace: List(VXML),
  remaining: List(VXML),
) -> List(VXML) {
  case remaining {
    [] -> {
      case last_dude {
        None -> {
          assert [] == whitespace
          already_processed |> list.reverse
        }
        Some(dude) -> {
          list.append(whitespace, [dude, ..already_processed])
          |> list.reverse
        }
      }
    }

    [T(_, _) as first, ..rest] -> {
      case last_dude {
        None -> {
          // *
          // absorb the T-node into already_processed
          // *
          assert [] == whitespace
          accumulator(
            inner,
            [first, ..already_processed],
            None,
            [],
            rest,
          )
        }
        Some(dude) -> case infra.lines_are_whitespace(first.lines) {
          False -> {
            // *
            // flush whitespace & dude, start over
            // *
            accumulator(
              inner,
              case whitespace {
                [] -> [first, dude, ..already_processed]
                [one] -> [first, one, dude, ..already_processed]
                _ -> [first, ..list.append(whitespace, [dude, ..already_processed])]
              },
              None,
              [],
              rest,
            )
          }
          True ->  {
            // *
            // add to whitespace
            // *
            accumulator(
              inner,
              already_processed,
              last_dude,
              [first, ..whitespace],
              rest,
            )
          }
        }
      }
    }

    [V(_, tag, _, _) as first, ..rest] if tag != inner -> {
      case last_dude {
        None -> {
          // *
          // absorb the V-node into already_processed
          // *
          assert [] == whitespace
          accumulator(
            inner,
            [first, ..already_processed],
            None,
            [],
            rest,
          )
        }
        Some(dude) -> {
          // *
          // flush whitespace & dude, start over
          // *
          accumulator(
            inner,
            case whitespace {
              [] -> [first, dude, ..already_processed]
              [one] -> [first, one, dude, ..already_processed]
              _ -> [first, ..list.append(whitespace, [dude, ..already_processed])]
            },
            None,
            [],
            rest,
          )
        }
      }
    }

    [V(_, tag, _, c2) as first, ..rest] -> {
      assert tag == inner
      case last_dude {
        None -> {
          // *
          // let last_dude = Some(first)
          // *
          assert [] == whitespace
          accumulator(
            inner,
            already_processed,
            Some(first),
            [],
            rest,
          )
        }
        Some(dude) -> {
          // *
          // bridge dude -> first
          // *
          let assert V(_, _, _, c1) = dude
          let #(c1_last_lines, c1_others_reversed) = case c1 |> list.reverse {
            [T(..) as last, ..rest] -> #(last.lines |> list.reverse, rest)
            anything_else -> #([], anything_else)
          }
          let #(c2_first_lines, c2_others) = case c2 {
            [T(..) as first, ..rest] -> #(first.lines, rest)
            _ -> #([], c2)
          }
          let whitespace = list.map(whitespace, fn(w) {
            let assert T(_, lines) = w
            lines |> list.reverse
          })
          let bridge_lines = infra.last_to_first_concatenation_in_list_list_of_lines_where_all_but_last_list_are_already_reversed_v2(
            [
              c1_last_lines,
              ..whitespace,
            ],
            c2_first_lines,
          )
          let bridge_child = T(desugarer_blame(157), bridge_lines)
          let children = infra.pour([bridge_child, ..c1_others_reversed], c2_others)
          accumulator(
            inner,
            already_processed,
            Some(V(..dude, children: children)),
            [],
            rest,
          )
        }
      }
    }
  }
}

fn nodemap(
  node: VXML,
  inner: InnerParam,
) -> VXML {
  case node {
    T(_, _) -> node
    V(_, _, _, children) -> {
      let children = accumulator(inner, [], None, [], children)
      V(
        ..node,
        children: children,
      )
    }
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
  Ok(param)
}

type Param = String
//           ↖
//           tag
type InnerParam = Param

pub const name = "bridge_whitespace"
fn desugarer_blame(line_no: Int) { bl.Des([], name, line_no) }

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// Globs sibling nodes of the given tag together
/// when adjacent or separated only by text nodes
/// that contain whitespace. In more detail, when
/// two nodes are globbed together, the intervening
/// text nodes are concatenated in last-to-first-line
/// fashion with the last child of the first node and
/// the first child of the second node, if these
/// children are text, to form the "bridging child"
/// of the newly formed node.
pub fn constructor(param: Param) -> Desugarer {
  Desugarer(
    name: name,
    stringified_param: Some(ins(param)),
    stringified_outside: None,
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
  [
    infra.AssertiveTestData(
      param: "b",
      source:   "
                <> root
                  <> b
                    <>
                      \"hello1\"
                  <> b
                    <>
                      \"hello\"
                ",
      expected: "
                <> root
                  <> b
                    <>
                      \"hello1hello\"
                ",
    ),
    infra.AssertiveTestData(
      param: "b",
      source:   "
                <> root
                  <> b
                    <>
                      \"hello1\"
                  <>
                    \" \"
                  <> b
                    <>
                      \"hello\"
                ",
      expected: "
                <> root
                  <> b
                    <>
                      \"hello1 hello\"
                ",
    ),
    infra.AssertiveTestData(
      param: "b",
      source:   "
                <> root
                  <> b
                    <>
                      \"hello1\"
                      \"hello2\"
                  <>
                    \"\"
                    \"\"
                  <> b
                    <>
                      \"hello3\"
                      \"hello4\"
                ",
      expected: "
                <> root
                  <> b
                    <>
                      \"hello1\"
                      \"hello2\"
                      \"hello3\"
                      \"hello4\"
                ",
    ),
  ]
}

pub fn assertive_tests() {
  infra.assertive_test_collection_from_data(name, assertive_tests_data(), constructor)
}
