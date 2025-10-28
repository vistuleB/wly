import gleam/list
import gleam/option.{type Option}
import gleam/string.{inspect as ins}
import infrastructure.{
  type Desugarer,
  type DesugarerTransform,
  type DesugaringError,
  Desugarer,
} as infra
import nodemaps_2_desugarer_transforms as n2t
import vxml.{type VXML, T, V}
import blame.{type Blame, Src} as bl

fn pairing_msg(
  local: Blame,
  remote: Blame,
) -> String {
  case local, remote {
    Src(_, l, _, _, _), Src(_, r, _, _, _) if l == r ->
      "paired with --:" <> ins(remote.line_no) <> ":" <> ins(remote.char_no)
    _, _ ->
      "p.w. " <> bl.blame_digest(remote)
  }
}

fn accumulator(
  opening: String,
  closing: String,
  enclosing: String,
  unbridgeable: List(String),
  already_processed: List(VXML),
  last_opening: Option(VXML),
  after_last_opening: List(VXML),
  remaining: List(VXML),
) -> List(VXML) {
  case remaining {
    [] ->
      case last_opening {
        option.None -> {
          assert [] == after_last_opening
          already_processed |> list.reverse
        }
        option.Some(dude) -> {
          list.flatten([after_last_opening, [dude, ..already_processed]])
          |> list.reverse
        }
      }
    [T(_, _) as first, ..rest] ->
      case last_opening {
        option.None -> {
          // *
          // absorb the T-node into already_processed
          // *
          assert [] == after_last_opening
          accumulator(
            opening,
            closing,
            enclosing,
            unbridgeable,
            [first, ..already_processed],
            option.None,
            [],
            rest,
          )
        }
        option.Some(_) ->
          // *
          // absorb the T-node into after_last_opening
          // *
          accumulator(
            opening,
            closing,
            enclosing,
            unbridgeable,
            already_processed,
            last_opening,
            [first, ..after_last_opening],
            rest,
          )
      }
    [V(_, tag, _, _) as first, ..rest] ->
      // dispatch most common case first,
      // even if it's redundant with further cases:
      case last_opening == option.None && tag != opening {
        True -> {
          assert [] == after_last_opening
          accumulator(
            opening,
            closing,
            enclosing,
            unbridgeable,
            [first, ..already_processed],
            option.None,
            [],
            rest,
          )
        }
        False -> {
          case list.contains(unbridgeable, tag) {
            True -> {
              case last_opening {
                option.None -> {
                  assert [] == after_last_opening
                  accumulator(
                    opening,
                    closing,
                    enclosing,
                    unbridgeable,
                    [first, ..already_processed],
                    option.None,
                    [],
                    rest,
                  )
                }
                option.Some(x) -> {
                  accumulator(
                    opening,
                    closing,
                    enclosing,
                    unbridgeable,
                    [first, ..infra.pour(after_last_opening, [x, ..already_processed])],
                    option.None,
                    [],
                    rest,
                  )
                }
              }
            }
            False -> {
              case tag == opening, tag == closing {
                False, False ->
                  // *
                  // treat the V-node like the T-node above
                  // *
                  case last_opening {
                    option.None -> {
                      // *
                      // absorb the V-node into already_processed
                      // *
                      assert [] == after_last_opening
                      accumulator(
                        opening,
                        closing,
                        enclosing,
                        unbridgeable,
                        [first, ..already_processed],
                        option.None,
                        [],
                        rest,
                      )
                    }
                    option.Some(_) ->
                      // *
                      // absorb the V-node into after_last_opening
                      // *
                      accumulator(
                        opening,
                        closing,
                        enclosing,
                        unbridgeable,
                        already_processed,
                        last_opening,
                        [first, ..after_last_opening],
                        rest,
                      )
                  }
                True, False ->
                  case last_opening {
                    option.None -> {
                      // *
                      // we make the V-node the new value of last_opening
                      // *
                      assert [] == after_last_opening
                      accumulator(
                        opening,
                        closing,
                        enclosing,
                        unbridgeable,
                        already_processed,
                        option.Some(first),
                        [],
                        rest,
                      )
                    }
                    option.Some(dude) ->
                      // *
                      // we discard the previous last_opening and his followers and make the V-node the new value of last_opening
                      // *
                      accumulator(
                        opening,
                        closing,
                        enclosing,
                        unbridgeable,
                        list.flatten([after_last_opening, [dude, ..already_processed]]),
                        option.Some(first),
                        [],
                        rest,
                      )
                  }
                False, True ->
                  case last_opening {
                    option.None -> {
                      // *
                      // we absorb the V-node into already_processed
                      // *
                      assert [] == after_last_opening
                      accumulator(
                        opening,
                        closing,
                        enclosing,
                        unbridgeable,
                        [first, ..already_processed],
                        option.None,
                        [],
                        rest,
                      )
                    }
                    option.Some(dude) ->
                      // *
                      // we do a pairing
                      // *
                      accumulator(
                        opening,
                        closing,
                        enclosing,
                        unbridgeable,
                        [
                          V(
                            dude.blame |> bl.append_comment(pairing_msg(dude.blame, first.blame)),
                            enclosing,
                            first.attrs, // we only take the attrs of the closing tag, for now (we're lazy)
                            after_last_opening |> list.reverse,
                          ),
                          ..already_processed
                        ],
                        option.None,
                        [],
                        rest,
                      )
                  }
                True, True ->
                  case last_opening {
                    option.None -> {
                      // *
                      // we make the V-node the new value of last_opening
                      // *
                      assert [] == after_last_opening
                      accumulator(
                        opening,
                        closing,
                        enclosing,
                        unbridgeable,
                        already_processed,
                        option.Some(first),
                        [],
                        rest,
                      )
                    }
                    option.Some(dude) ->
                      // *
                      // we do a pairing
                      // *
                      accumulator(
                        opening,
                        closing,
                        enclosing,
                        unbridgeable,
                        [
                          V(
                            dude.blame |> bl.append_comment(pairing_msg(dude.blame, first.blame)),
                            enclosing,
                            first.attrs, // we only take the attrs of the closing tag, for now (we're lazy),
                            after_last_opening |> list.reverse,
                          ),
                          ..already_processed
                        ],
                        option.None,
                        [],
                        rest,
                      )
                  }
              }
            }
          }
        }
      }

  }
}

fn nodemap(
  node: VXML,
  inner: InnerParam,
) -> VXML {
  let #(opening, closing, enclosing, unbridgeable) = inner
  case node {
    T(_, _) -> node
    V(blame, tag, attrs, children) -> {
      let new_children =
        accumulator(
          opening,
          closing,
          enclosing,
          unbridgeable,
          [],
          option.None,
          [],
          children,
        )
      V(blame, tag, attrs, new_children)
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

type Param = #(String,   String,   String,     List(String))
//             ↖         ↖         ↖           ↖
//             opening   closing   enclosing   list of
//             tag       tag       tag         "unbridgeable" tags
type InnerParam = Param

pub const name = "pair"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// pairs opening and closing bookend tags by
/// wrapping content between them in an enclosing
/// tag
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
