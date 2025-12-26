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
import vxml.{type VXML, Line, T, V}
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
            [T(..) as last, ..rest] -> #(last.lines, rest)
            anything_else -> #([], anything_else)
          }
          let #(c2_first_lines, c2_others) = case c2 {
            [T(..) as first, ..rest] -> #(first.lines, rest)
            _ -> #([], c2)
          }
          let any_space_or_newline = list.any(
            whitespace,
            fn (w) {
              let assert T(_, lines) = w
              case lines {
                [] -> panic
                [one] -> one.content != ""
                _ -> True
              }
            }
          )
          let whitespace = case any_space_or_newline {
            True -> [[Line(desugarer_blame(158), " ")]]
            False -> []
          }
          let all_lists = list.flatten([
            [c1_last_lines],
            whitespace,
            [c2_first_lines]
          ])
          |> list.filter(fn(x) { x != [] })
          let bridge_lines = case all_lists {
            [] -> []
            _ -> infra.last_to_first_concatenation_in_list_list_lines(all_lists)
          }
          let children = case bridge_lines {
            [] -> infra.pour(c1_others_reversed, c2_others)
            _ -> {
              let bridge_child = T(desugarer_blame(174), bridge_lines)
              infra.pour([bridge_child, ..c1_others_reversed], c2_others)
            }
          }
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

fn nodemap_factory(inner: InnerParam) -> n2t.OneToOneNoErrorNodemap {
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

pub const name = "bridge_whitespace_single_space"
fn desugarer_blame(line_no: Int) { bl.Des([], name, line_no) }

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// Globs sibling nodes of the given tag together
/// when adjacent or separated only by text nodes
/// that contain whitespace. In more detail:
/// 
/// - when there are no whitespace text nodes between
///   the two adjacent siblings, the siblings are
///   concatated in last-to-first-line fashion
///   (vis-a-vis their own first & last child text node
///   if any, respectively)
/// 
/// - in the remaining case, the intervening whitespace
///   nodes are replaced by a single space text node,
///   and a similar last-to-first line concatenation
///   ensues among the last child text node of the
///   first node, if any, the single space text node, 
///   first child text node of the second node, if 
///   any
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
                      'hello1'
                  <> b
                    <>
                      'hello2'
                ",
      expected: "
                <> root
                  <> b
                    <>
                      'hello1hello2'
                ",
    ),
    infra.AssertiveTestData(
      param: "b",
      source:   "
                <> root
                  <> b
                    <>
                      'hello1'
                  <>
                    ''
                  <> b
                    <>
                      'hello2'
                ",
      expected: "
                <> root
                  <> b
                    <>
                      'hello1hello2'
                ",
    ),
    infra.AssertiveTestData(
      param: "b",
      source:   "
                <> root
                  <> b
                    <>
                      'hello1'
                  <>
                    ' '
                  <> b
                    <>
                      'hello2'
                ",
      expected: "
                <> root
                  <> b
                    <>
                      'hello1 hello2'
                ",
    ),
    infra.AssertiveTestData(
      param: "b",
      source:   "
                <> root
                  <> b
                    <>
                      'hello1'
                      'hello2'
                  <>
                    ''
                    ''
                  <> b
                    <>
                      'hello3'
                      'hello4'
                ",
      expected: "
                <> root
                  <> b
                    <>
                      'hello1'
                      'hello2 hello3'
                      'hello4'
                ",
    ),
    infra.AssertiveTestData(
      param: "b",
      source:   "
                <> root
                  <> b
                    <>
                      'hello1'
                      'hello2'
                    <> i
                      <>
                        'hey1'
                  <>
                    ''
                    ''
                  <> b
                    <> i
                      <>
                        'hey2'
                    <>
                      'hello3'
                      'hello4'
                ",
      expected: "
                <> root
                  <> b
                    <>
                      'hello1'
                      'hello2'
                    <> i
                      <>
                        'hey1'
                    <>
                      ' '
                    <> i
                      <>
                        'hey2'
                    <>
                      'hello3'
                      'hello4'
                ",
    ),
    infra.AssertiveTestData(
      param: "b",
      source:   "
                <> root
                  <> b
                    <>
                      'hello1'
                      'hello2'
                  <>
                    ''
                    'caramel'
                  <> b
                    <>
                      'hello3'
                      'hello4'
                ",
      expected: "
                <> root
                  <> b
                    <>
                      'hello1'
                      'hello2'
                  <>
                    ''
                    'caramel'
                  <> b
                    <>
                      'hello3'
                      'hello4'
                ",
    ),
  ]
}

pub fn assertive_tests() {
  infra.assertive_test_collection_from_data(name, assertive_tests_data(), constructor)
}
