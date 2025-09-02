import gleam/list
import gleam/option
import gleam/string
import infrastructure.{type Desugarer, Desugarer, type DesugarerTransform, type DesugaringError} as infra
import nodemaps_2_desugarer_transforms as n2t
import vxml.{type VXML, Attribute, V, T}
import blame.{type Blame} as bl

const had_href_child = Attribute(bl.Des([], name, 9), "had_href_child", "true")

fn start_node(blame: Blame) {
  V(blame, "__StartTokenizedT", [], [])
}

fn word_node(blame: Blame, word: String) {
  V(blame, "__OneWord", [Attribute(blame, "val", word)], [])
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
  past_tokens: List(VXML),
  current_blame: Blame,
  leftover: String,
) -> List(VXML) {
  case string.split_once(leftover, " ") {
    Ok(#("", after)) -> tokenize_string_acc(
      [space_node(current_blame), ..past_tokens],
      bl.advance(current_blame, 1),
      after,
    )
    Ok(#(before, after)) -> tokenize_string_acc(
      [space_node(current_blame), word_node(current_blame, before), ..past_tokens],
      bl.advance(current_blame, string.length(before) + 1),
      after,
    )
    Error(Nil) -> case leftover == "" {
      True -> past_tokens |> list.reverse
      False -> [word_node(current_blame, leftover), ..past_tokens] |> list.reverse
    }
  }
}

fn tokenize_t(vxml: VXML) -> List(VXML) {
  let assert T(blame, lines) = vxml
  lines
  |> list.index_map(fn(line, i) {
    tokenize_string_acc(
      [],
      line.blame,
      line.content,
    )
    |> list.prepend(case i == 0 {
      True -> start_node(line.blame)
      False -> newline_node(line.blame)
    })
  })
  |> list.flatten
  |> list.append([end_node(blame)])
}

fn tokenize_if_t_or_has_href_attr(vxml: VXML) -> List(VXML) {
  case vxml {
    T(_, _) -> tokenize_t(vxml)
    V(_, _, attrs, children) -> case infra.attributes_have_key(attrs, "href") {
      True -> [V(..vxml, children: tokenize_children(children))]
      False -> [vxml]
    }
  }
}

fn tokenize_children(children: List(VXML)) -> List(VXML) {
  list.map(children, tokenize_if_t_or_has_href_attr) |> list.flatten
}

fn nodemap(
  vxml: VXML,
) -> VXML {
  case vxml {
    T(_, _) -> vxml
    V(_, _, attrs, children) -> {
      case list.any(children, infra.is_v_and_has_attribute_with_key(_, "href")) {
        False -> vxml
        True -> {
          let attrs = [had_href_child, ..attrs]
          let children = tokenize_children(children)
          V(..vxml, attributes: attrs, children: children)
        }
      }
    }
  }
}

fn nodemap_factory(_inner: InnerParam) -> n2t.OneToOneNoErrorNodeMap {
  nodemap
}

fn transform_factory(inner: InnerParam) -> DesugarerTransform {
  nodemap_factory(inner)
  |> n2t.one_to_one_no_error_nodemap_2_desugarer_transform()
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(param)
}

type Param = Nil
type InnerParam = Param

pub const name = "tokenize_href_surroundings"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
///
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
  [
    infra.AssertiveTestDataNoParam(
      source: "
            <> testing
              <> zz
                href=bla
                <>
                  \"first line\"
                  \"second line\"
                <>
                  \"third line\"

                <> inside
                  <>
                    \"some text\"
      ",
      expected: "
            <> testing
              had_href_child=true
              <> zz
                href=bla
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
                    \"some text\"
      ",
    ),
    infra.AssertiveTestDataNoParam(
      source: "
            <> testing
              <> zz
                href=true
                <>
                  \"first  line\"
                  \"second  \"
                  \"   line\"
      ",
      expected: "
            <> testing
              had_href_child=true
              <> zz
                href=true
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
    infra.AssertiveTestDataNoParam(
      source: "
            <> testing
              <> zz
                href=cx
                <>
                  \"\"
                  \"\"
      ",
      expected: "
            <> testing
              had_href_child=true
              <> zz
                href=cx
                <> __StartTokenizedT
                <> __OneNewLine
                <> __EndTokenizedT
      ",
    )
  ]
}

pub fn assertive_tests() {
  infra.assertive_test_collection_from_data_no_param(name, assertive_tests_data(), constructor)
}
