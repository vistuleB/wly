import gleam/option
import gleam/list
import gleam/string.{inspect as ins}
import infrastructure.{type Desugarer, Desugarer, type DesugarerTransform, type DesugaringError} as infra
import nodemaps_2_desugarer_transforms as n2t
import vxml.{type VXML, type TextLine, V, T, TextLine}
import blame.{type Blame} as bl
import on
import splitter as sp

fn t_1_line(
  b: Blame,
  c: String
) -> VXML {
  T(b, [TextLine(b, c)])
}

fn get_to_zero(
  current: Int,
  cumulated: String,
  remaining: String,
) -> Result(#(String, String), Nil) {
  use <- on.true_false(
    current == 0,
    Ok(#(cumulated, remaining))
  )
  assert current > 0
  let splitter = sp.new([")", "("])
  let #(before, there, after) = sp.split(splitter, remaining)
  case there {
    "" -> Error(Nil)
    ")" -> get_to_zero(current - 1, cumulated <> before <> there, after)
    "(" -> get_to_zero(current + 1, cumulated <> before <> there, after)
    _ -> panic
  }
}

fn line_map(
  l: TextLine,
  inner: InnerParam,
) -> List(VXML) {
  let blame = l.blame
  let early_return = [T(blame, [l])]

  use #(before, original_after) <- on.error_ok(
    string.split_once(l.content, "]("),
    fn(_) { early_return },
  )

  use #(maybe_href, after) <- on.error_ok(
    string.split_once(original_after, ")"),
    fn(_) { early_return },
  )

  use _ <- on.ok_error(
    string.split_once(maybe_href, " "),
    fn(pair) {
      let #(href_bef, href_af) = pair
      let continue_with_bef = before <> ")[" <> href_bef <> " "
      let continue_with_af = href_af <> ")" <> after
      [
        t_1_line(blame, continue_with_bef),
        ..line_map(TextLine(bl.advance(blame, string.length(continue_with_bef)), continue_with_af), inner)
      ]
    }
  )

  // try for cheap success:
  use <- on.lazy_false_true(
    string.contains(maybe_href, "("),
    fn() {
      [ 
        t_1_line(blame, before),
        V(
          bl.advance(blame, string.length(before) + 2),
          inner,
          [vxml.Attribute(desugarer_blame(77), "href", maybe_href)],
          [],
        ),
        ..line_map(
          TextLine(
            bl.advance(blame, string.length(before) + string.length(maybe_href) + 3),
            after,
          ),
          inner,
        )
      ]
    }
  )

  // do complete homework:
  case get_to_zero(1, "", original_after) {
    Ok(#(href, after)) -> {
      let href = string.drop_end(href, 1)
      [
        t_1_line(blame, before),
        V(
          bl.advance(blame, string.length(before) + 2),
          inner,
          [vxml.Attribute(desugarer_blame(100), "href", href)],
          [],
        ),
        ..line_map(
          TextLine(
            bl.advance(blame, string.length(before) + string.length(href) + 3),
            after,
          ),
          inner,
        )
      ]
    }
    Error(_) -> {
      let continue_with_bef = before <> ")["
      let continue_with_af = original_after
      [
        t_1_line(blame, continue_with_bef),
        ..line_map(TextLine(bl.advance(blame, string.length(continue_with_bef)), continue_with_af), inner)
      ]
    }
  }
}

fn nodemap(
  vxml: VXML,
  inner: InnerParam,
) -> List(VXML) {
  case vxml {
    V(_, _, _, _) -> [vxml]
    T(_, lines) ->
      lines
      |> list.flat_map(line_map(_, inner))
      |> infra.plain_concatenation_in_list
  }
}

fn nodemap_factory(inner: InnerParam) -> n2t.OneToManyNoErrorNodeMap {
  nodemap(_, inner)
}

fn transform_factory(inner: InnerParam, outside: List(String)) -> DesugarerTransform {
  nodemap_factory(inner)
  |> n2t.one_to_many_no_error_nodemap_2_desugarer_transform_with_forbidden(outside)
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(param)
}

type Param = String
type InnerParam = Param

pub const name = "markdown_link_closing_handrolled_splitter"
fn desugarer_blame(line_no: Int) { bl.Des([], name, line_no) }

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// splits text nodes by regexp with group-by-group
/// replacement instructions; keeps out of subtrees
/// rooted at tags given by its second argument
pub fn constructor(param: Param, outside: List(String)) -> Desugarer {
  Desugarer(
    name: name,
    stringified_param: option.Some(param),
    stringified_outside: option.Some(ins(outside)),
    transform: case param_to_inner_param(param) {
      Error(error) -> fn(_) { Error(error) }
      Ok(inner) -> transform_factory(inner, outside)
    },
  )
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
fn assertive_tests_data() -> List(infra.AssertiveTestDataWithOutside(Param)) {
  []
}

pub fn assertive_tests() {
  infra.assertive_test_collection_from_data_with_outside(name, assertive_tests_data(), constructor)
}
