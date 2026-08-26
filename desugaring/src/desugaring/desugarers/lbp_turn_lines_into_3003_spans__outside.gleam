import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
  type TrafficLight, Continue, GoBack,
}
import desugaring/nodemaps_2_transform as n2t
import gleam/list
import gleam/string.{inspect as ins}
import on
import vxml.{type Line, type VXML, Attr, Line, T, V}
import vxml/blame as bl

pub const name = "lbp_turn_lines_into_3003_spans__outside"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Converts source lines into 3003 tooltip spans carrying
/// location information outside configured subtrees.
pub fn constructor(param: Param, outside: List(String)) -> Desugarer {
  authoring.desugarer_with_outside(
    name: name,
    param: param,
    outside: outside,
    prepare: param_to_inner_param(_, outside),
    transform: inner_param_to_transform,
  )
}

// Local path of the source document.
type Param =
  String

type InnerParam =
  #(String, List(String))

fn param_to_inner_param(
  param: Param,
  outside: List(String),
) -> Result(InnerParam, DesugaringError) {
  Ok(#(param, outside))
}

fn inner_param_to_transform(
  inner: InnerParam,
  outside: List(String),
) -> DesugarerTransform {
  nodemap_factory(inner)
  |> n2t.early_return_one_to_many_no_error_nodemap_2_desugarer_transform_with_forbidden(
    outside,
  )
}

fn nodemap_factory(
  inner: InnerParam,
) -> n2t.EarlyReturnOneToManyNoErrorNodemap {
  nodemap(_, inner)
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
      GoBack,
    )
    _ -> #([vxml], Continue)
  }
}

const container_classname = "t-3003-c"

const tooltip_classname = "t-3003"

const b = bl.Des([], name, 82)

const newline_t = T(b, [Line(b, ""), Line(b, "")])

const container_attrs = [Attr(b, "class", container_classname)]

const tooltip_attrs = [Attr(b, "class", tooltip_classname)]

fn get_location(blame: bl.Blame, prefix: String) -> Result(String, Nil) {
  case blame {
    bl.Src(_, path, line_no, char_no, _) ->
      Ok(prefix <> path <> ":" <> ins(line_no) <> ":" <> ins(char_no))
    _ -> Error(Nil)
  }
}

fn wrap_with_tooltip(location: String, content: VXML) -> VXML {
  V(b, "span", container_attrs, [
    content,
    V(b, "span", tooltip_attrs, [
      T(b, [Line(b, location)]),
    ]),
  ])
}

fn line_to_tooltip_span(line: Line, inner: InnerParam) -> #(Bool, VXML) {
  let t = T(line.blame, [Line(line.blame, line.content)])
  use <- on.eager_true_false(line.content == "", #(False, t))
  use location <- on.eager_error_ok(get_location(line.blame, inner.0), #(
    False,
    t,
  ))
  #(True, wrap_with_tooltip(location, t))
}

fn edit_lines(lines: List(Line), inner: InnerParam) -> #(Bool, List(VXML)) {
  let #(acc, vxmls) =
    list.map_fold(lines, False, fn(acc, line) {
      case acc {
        False -> line_to_tooltip_span(line, inner)
        True -> #(True, T(line.blame, [Line(line.blame, line.content)]))
      }
    })
  case acc {
    True -> #(
      True,
      vxmls
        |> core.plain_concatenation_in_list
        |> list.intersperse(newline_t),
    )
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
    [V(_, tag, _, children) as first, ..rest] -> {
      case list.contains(inner.1, tag) {
        True -> {
          let #(z, q) = edit_first_t_descendant(rest, inner)
          #(z, [first, ..q])
        }
        False -> {
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
  }
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊

fn assertive_tests_data() -> List(core.AssertiveTestDataWithOutside(Param)) {
  [
    // note: 'tst.source' is the filename assigned by the
    // assertive test runner, which is why
    // '../path/to/content/tst.source' shows up in the expected
    // output
    core.AssertiveTestDataWithOutside(
      param: "../path/to/content/",
      outside: ["TOC"],
      source: "
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
                ",
    ),
  ]
}

pub fn assertive_tests() {
  core.assertive_test_collection_from_data_with_outside(
    name,
    assertive_tests_data(),
    constructor,
  )
}
