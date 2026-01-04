import blame as bl
import gleam/list
import gleam/option
import gleam/string.{inspect as ins}
import infrastructure.{
  type Desugarer,
  type DesugaringError,
  type DesugarerTransform,
  type TrafficLight,
  Desugarer,
  Continue,
  GoBack
} as infra
import nodemaps_2_desugarer_transforms as n2t
import on
import vxml.{ type Line, type VXML, Attr, Line, T, V }

const container_classname = "t-3003-c"
const tooltip_classname = "t-3003"
const b = bl.Des([], name, 14)
const newline_t = T(b, [Line(b, ""), Line(b, "")])

fn get_location(blame: bl.Blame, prefix: String) -> Result(String, Nil) {
  case blame {
    bl.Src(_, path, line_no, char_no, _) ->
      Ok(prefix <> path <> ":" <> ins(line_no) <> ":" <> ins(char_no))
    _ -> Error(Nil)
  }
}

fn wrap_with_tooltip(
  blame: bl.Blame,
  location: String,
  content: VXML,
) -> VXML {
  V(blame, "span", [Attr(blame, "class", container_classname)], [
    content,
    V(blame, "span", [Attr(blame, "class", tooltip_classname)], [
      T(blame, [Line(blame, location)]),
    ]),
  ])
}

fn line_to_tooltip_span(line: Line, inner: InnerParam) -> #(Bool, VXML) {
  let content = T(line.blame, [Line(line.blame, line.content)])
  use location <- on.eager_error_ok(
    get_location(line.blame, inner),
    #(False, content),
  )
  #(True, wrap_with_tooltip(line.blame, location, content))
}

fn edit_lines(lines: List(Line), inner: InnerParam) -> #(Bool, List(VXML)) {
  let #(acc, vxmls) = list.map_fold(
    lines,
    False,
    fn (acc, line) {
      case acc {
        False -> line_to_tooltip_span(line, inner)
        True -> #(True, T(line.blame, [Line(line.blame, line.content)]))
      }
    }
  )
  case acc {
    True -> #(True, vxmls |> infra.plain_concatenation_in_list |> list.intersperse(newline_t))
    False -> #(False, [])
  }
}

fn edit_first_t_descendant(
  children: List(VXML),
  inner: InnerParam,
) -> #(Bool, List(VXML)) {
  case children {
    [] -> #(False, [])
    [T(..) as first, ..rest] -> {
      let #(z, replacements) = edit_lines(first.lines, inner)
      case z {
        True -> #(True, list.append(replacements, rest))
        False -> {
          let #(z, q) = edit_first_t_descendant(rest, inner)
          #(z, [first, ..q])
        }
      }
    }
    [V(_, _, _, children) as first, ..rest] -> {
      case edit_first_t_descendant(children, inner) {
        #(True, stuff) -> #(True, [V(..first, children: stuff), ..rest])
        #(False, _) -> {
          let #(z, q) = edit_first_t_descendant(rest, inner)
          #(z, [first, ..q])
        }
      }
    }
  }
}

fn nodemap(vxml: VXML, inner: InnerParam) -> #(List(VXML), TrafficLight) {
  case vxml {
    V(_, "OuterP", _, children) -> {
      let #(_, children) = edit_first_t_descendant(children, inner)
      #([V(..vxml, children: children)], GoBack)
    }
    T(_, lines) -> #(
      case edit_lines(lines, inner) {
        #(True, vxmls) -> vxmls
        _ -> [vxml]
      },
      GoBack
    )
    _ -> #([vxml], Continue)
  }
}

fn nodemap_factory(inner: InnerParam) -> n2t.EarlyReturnOneToManyNoErrorNodemap {
   nodemap(_, inner)
}

fn transform_factory(inner: InnerParam, outside: List(String)) -> DesugarerTransform {
  nodemap_factory(inner)
  |> n2t.early_return_one_to_many_no_error_nodemap_2_desugarer_transform_with_forbidden(outside)
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(param)
}

type Param = String
//           ↖
//           local path
//           of source
type InnerParam = Param

pub const name = "lbp_turn_lines_into_3003_spans"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53

/// breaks lines into span tooltips with location
/// information
pub fn constructor(param: Param, outside: List(String)) -> Desugarer {
  Desugarer(
    name: name,
    stringified_param: option.Some(ins(param)),
    stringified_outside: option.None,
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
  [
    // note 1: not sure if following test is correct
    // it was reverse-engineered from the desugarer's
    // output long after this desugarer had already
    // stopped being used (but it might be correct)
    //
    // note 2: 'test' is the filename assigned by the
    // infrastructure.gleam test runner, which is why 
    // '../path/to/content/test' shows up in the expected 
    // output
    infra.AssertiveTestDataWithOutside(
      param: "../path/to/content/",
      outside: ["TOC"],
      source:   "
                <> ArticleTitle
                  <>
                    'some text'
                    'more text'
                  <> i
                    <>
                      'more text'
                ",
      expected: "
                <> ArticleTitle
                  <> span
                    class=t-3003-c
                    <>
                      'some text'
                    <> span
                      class=t-3003
                      <>
                        '../path/to/content/tst.source:3:5'
                  <>
                    ''
                    ''
                  <>
                    'more text'
                  <> i
                    <> span
                      class=t-3003-c
                      <>
                        'more text'
                      <> span
                        class=t-3003
                        <>
                          '../path/to/content/tst.source:7:7'
                "
    ),
  ]
}

pub fn assertive_tests() {
  infra.assertive_test_collection_from_data_with_outside(name, assertive_tests_data(), constructor)
}
