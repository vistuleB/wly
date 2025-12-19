import gleam/list
import gleam/option
import gleam/string.{inspect as ins}
import infrastructure.{
  type Desugarer,
  type DesugaringError,
  type DesugarerTransform,
  Desugarer,
} as infra
import nodemaps_2_desugarer_transforms as n2t
import vxml.{ type Line, type VXML, Attr, Line, T, V }
import blame as bl
import on.{Return, Continue as Stay}

// remember to replace these names in tests,
// as well:
const container_classname = "t-3003-c"
const tooltip_classname = "t-3003"
const b = bl.Des([], name, 14)
const newline_t = T(b, [Line(b, ""), Line(b, "")])

fn line_to_tooltip_span(
  line: Line,
  inner: InnerParam,
) -> VXML {
  let location =
    inner <> case line.blame {
      bl.Src(..) -> {
        let assert bl.Src(_, path, line_no, char_no, _) = line.blame
        path <> ":" <> ins(line_no) <> ":" <> ins(char_no)
      }
      _ -> ""
    }

  use _ <- on.continue(case location == inner {
    True -> Return(T(line.blame, [line]))
    False -> Stay(Nil)
  })

  V(
    line.blame,
    "span",
    [Attr(line.blame, "class", container_classname)],
    [
      T(line.blame, [Line(line.blame, line.content)]),
      V(
        line.blame,
        "span",
        [
          Attr(line.blame, "class", tooltip_classname),
        ],
        [
          T(line.blame, [Line(line.blame, location)])
        ],
      ),
    ],
  )
}

fn bold_line_to_tooltip_span(
  vxml:VXML,
  inner: InnerParam
) -> VXML {
  case vxml {
    V(b1, "b", attr, [T(b2, [line, ..rest_lines]), ..children]) -> {
      let location =
        inner <> case line.blame {
          bl.Src(..) -> {
            let assert bl.Src(_, path, line_no, char_no, _) = line.blame
            path <> ":" <> ins(line_no) <> ":" <> ins(char_no)
          }
          _ -> ""
        }
    
      use _ <- on.continue(case location == inner {
        True -> Return(T(line.blame, [line]))
        False -> Stay(Nil)
      })
      
      V(
        vxml.blame,
        "span",
        [Attr(line.blame, "class", container_classname)],
        [
          V(b1, "b", attr, [T(line.blame, [Line(line.blame, line.content)]), newline_t, T(b2, rest_lines), ..children]),
          V(
            vxml.blame,
            "span",
            [
              Attr(line.blame, "class", tooltip_classname),
            ],
            [
              T(line.blame, [Line(line.blame, location)])
            ],
          ),
        ],
      )
    }
    _ -> vxml
    
  }
}

fn nodemap(
  vxml: VXML,
  ancestors: List(VXML),
  _: List(VXML),
  _: List(VXML), 
  _: List(VXML),
  inner: InnerParam,
) -> List(VXML) {
  case vxml {
    V(bl_outp, "OuterP", attr_outp, children) -> {
      case children {
        [V(_, "b", _,_) as v_bold, ..rest_children] -> {
          [V(
            bl_outp, 
            "OuterP", 
            attr_outp, 
            [bold_line_to_tooltip_span(v_bold, inner), ..rest_children])
          ]
        }
        [T(b3, [first_line, ..rest_lines]), ..rest_children] -> {
          [V(bl_outp, "OuterP", attr_outp,
          [line_to_tooltip_span(first_line, inner), newline_t, T(b3, rest_lines), ..rest_children])]
        }
        _ -> [vxml]
      }
    }
    T(_, lines) -> {
      let forbidden_ancestors = ["OuterP", "Math", "MathBlock"]
      case list.any(ancestors, fn(ancestor) { infra.is_v_and_tag_is_one_of(ancestor, forbidden_ancestors) }) {
        True -> [vxml]
        False -> {
          lines
            |> list.map(line_to_tooltip_span(_, inner))
            |> list.intersperse(newline_t)
        }
      }
    }
    _ -> [vxml]
  }
}

fn nodemap_factory(inner: InnerParam) -> n2t.FancyOneToManyNoErrorNodeMap {
   fn(vxml, ancestors, s1, s2, s3) { nodemap(vxml, ancestors, s1, s2, s3, inner) }
}

fn transform_factory(inner: InnerParam) -> DesugarerTransform {
  nodemap_factory(inner)
  |> n2t.fancy_one_to_many_no_error_nodemap_2_desugarer_transform()
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
    infra.AssertiveTestData(
      param: "../path/to/content/",
      source:   "
                <> root
                  <>
                    'some text'
                ",
      expected: "
                <> root
                  <> span
                    class=t-3003-c
                    <>
                      'some text'
                    <> span
                      class=t-3003
                      <>
                        '../path/to/content/tst.source:3:5'
                "
    ),
  ]
}

pub fn assertive_tests() {
  infra.assertive_test_collection_from_data(name, assertive_tests_data(), constructor)
}
