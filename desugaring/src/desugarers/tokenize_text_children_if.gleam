import gleam/list
import gleam/option
import gleam/string.{inspect as ins}
import infrastructure.{type Desugarer, Desugarer, type DesugarerTransform, type DesugaringError} as infra
import nodemaps_2_desugarer_transforms as n2t
import splitter.{type Splitter}
import vxml.{type VXML, Attr, V, T}
import blame.{type Blame} as bl

fn start_node(blame: Blame) {
  V(blame, "__StartTokenizedT", [], [])
}

fn word_node(blame: Blame, word: String) {
  V(blame, "__OneWord", [Attr(desugarer_blame(15), "val", word)], [])
}

fn space_node(blame: Blame) {
  V(blame, "__OneSpace", [], [])
}

fn newline_node(blame: Blame) {
  V(blame, "__OneNewLine", [], [])
}

fn end_node(blame: Blame) {
  V(blame, "__EndTokenizedT", [], [])
}

fn tokenize_string_acc(
  opening_punctuation_splitter: Splitter,
  past_tokens: List(VXML),
  current_blame: Blame,
  leftover: String,
) -> List(VXML) {
  case splitter.split(opening_punctuation_splitter, leftover) {
    #(_, "", _) ->
      case leftover == "" {
        True -> past_tokens |> list.reverse
        False ->
          [word_node(current_blame, leftover), ..past_tokens] |> list.reverse
      }
    #("", " ", after) ->
      tokenize_string_acc(
        opening_punctuation_splitter,
        [space_node(current_blame), ..past_tokens],
        bl.advance(current_blame, 1),
        after,
      )
    #(before, " ", after) ->
      tokenize_string_acc(
        opening_punctuation_splitter,
        [
          space_node(current_blame),
          word_node(current_blame, before),
          ..past_tokens
        ],
        bl.advance(current_blame, string.length(before) + 1),
        after,
      )
    #("", non_space_punctuation, after) ->
      tokenize_string_acc(
        opening_punctuation_splitter,
        [
          word_node(current_blame, non_space_punctuation),
          ..past_tokens
        ],
        bl.advance(current_blame, 1),
        after,
      )
    #(before, non_space_punctuation, after) ->
      tokenize_string_acc(
        opening_punctuation_splitter,
        [
          word_node(current_blame, before),
          word_node(current_blame, non_space_punctuation),
          ..past_tokens
        ],
        bl.advance(current_blame, string.length(before) + 1),
        after,
      )
  }
}

fn tokenize_t(opening_punctuation_splitter: Splitter, vxml: VXML) -> List(VXML) {
  let assert T(blame, lines) = vxml
  lines
  |> list.index_map(fn(line, i) {
    tokenize_string_acc(opening_punctuation_splitter, [], line.blame, line.content)
    |> list.prepend(case i == 0 {
      True -> start_node(line.blame)
      False -> newline_node(line.blame)
    })
  })
  |> list.flatten
  |> list.append([end_node(blame)])
}

fn tokenize_if_t(opening_punctuation_splitter: Splitter, vxml: VXML) -> List(VXML) {
  case vxml {
    T(_, _) -> tokenize_t(opening_punctuation_splitter, vxml)
    _ -> [vxml]
  }
}

fn nodemap(
  vxml: VXML,
  inner: InnerParam,
) -> VXML {
  case vxml {
    T(_, _) -> vxml
    V(_, _, _, children) -> case inner.0(vxml) {
      False -> vxml
      True -> {
        let children = list.map(children, fn(vxml) { tokenize_if_t(inner.1, vxml)} ) |> list.flatten
        V(..vxml, children: children)
      }
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
  let opening_punctuation_splitter: Splitter = splitter.new([" ", "(", "[", "—"])
  Ok(#(param, opening_punctuation_splitter))
}

type Param = fn(VXML) -> Bool
type InnerParam = #(Param, Splitter)

pub const name = "tokenize_text_children_if"
fn desugarer_blame(line_no: Int) { bl.Des([], name, line_no) }

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
///
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
  let test_param = fn(vxml) {
    let assert V(_, t, _, _) = vxml
    t == "a"
  }
  [
    infra.AssertiveTestData(
      param: test_param,
      source: "
                <> testing
                  <> a
                    <>
                      'first line'
                      'second line'
                    <>
                      'third line'
                    <> inside
                      <>
                        'some text'
                ",
      expected: "
                <> testing
                  <> a
                    <> __StartTokenizedT
                    <> __OneWord
                      val=first
                    <> __OneSpace
                    <> __OneWord
                      val=line
                    <> __OneNewLine
                    <> __OneWord
                      val=second
                    <> __OneSpace
                    <> __OneWord
                      val=line
                    <> __EndTokenizedT
                    <> __StartTokenizedT
                    <> __OneWord
                      val=third
                    <> __OneSpace
                    <> __OneWord
                      val=line
                    <> __EndTokenizedT
                    <> inside
                      <>
                        'some text'
                ",
    ),
    infra.AssertiveTestData(
      param: test_param,
      source: "
            <> testing
              <> a
                <>
                  'first  line'
                  'second  '
                  '   line'
      ",
      expected: "
            <> testing
              <> a
                <> __StartTokenizedT
                <> __OneWord
                  val=first
                <> __OneSpace
                <> __OneSpace
                <> __OneWord
                  val=line
                <> __OneNewLine
                <> __OneWord
                  val=second
                <> __OneSpace
                <> __OneSpace
                <> __OneNewLine
                <> __OneSpace
                <> __OneSpace
                <> __OneSpace
                <> __OneWord
                  val=line
                <> __EndTokenizedT
      ",
    ),
    infra.AssertiveTestData(
      param: test_param,
      source: "
            <> testing
              <> a
                <>
                  ''
                  ''
      ",
      expected: "
            <> testing
              <> a
                <> __StartTokenizedT
                <> __OneNewLine
                <> __EndTokenizedT
      ",
    )
  ]
}

pub fn assertive_tests() {
  infra.assertive_test_collection_from_data(name, assertive_tests_data(), constructor)
}
