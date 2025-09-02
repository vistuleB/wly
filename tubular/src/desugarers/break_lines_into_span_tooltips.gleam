import gleam/list
import gleam/option
import gleam/string.{inspect as ins}
import infrastructure.{ type Desugarer, Desugarer, type DesugarerTransform, type DesugaringError } as infra
import nodemaps_2_desugarer_transforms as n2t
import vxml.{ type TextLine, type VXML, Attribute, TextLine, T, V }
import blame as bl

fn line_to_tooltip_span(
  line: TextLine,
  inner: InnerParam,
) -> VXML {
  let location =
    inner <> case line.blame {
      bl.Src(_, _, _, _) -> {
        let assert bl.Src(_, path, line_no, char_no) = line.blame
        path <> ":" <> ins(line_no) <> ":" <> ins(char_no)
      }
      _ -> ""
    }
  V(
    line.blame,
    "span",
    [Attribute(line.blame, "class", "tooltip-3003-container")],
    [
      V(
        line.blame,
        "span",
        [
          Attribute(line.blame, "class", "tooltip-3003-text")
        ],
        [
          T(line.blame, [TextLine(line.blame, line.content)])
        ],
      ),
      V(
        line.blame,
        "span",
        [
          Attribute(line.blame, "class", "tooltip-3003"),
          Attribute(line.blame, "onClick", "sendCmdTo3003('code --goto " <> location <> "');"),
        ],
        [
          T(line.blame, [TextLine(line.blame, location)])
        ],
      ),
    ],
  )
}

fn nodemap(
  vxml: VXML,
  inner: InnerParam,
) -> List(VXML) {
  case vxml {
    T(blame, lines) -> {
      [
        V(
          blame,
          "span",
          [],
          lines
            |> list.map(line_to_tooltip_span(_, inner))
            |> list.intersperse(
              T(blame, [TextLine(blame, ""), TextLine(blame, "")]),
            ),
        ),
      ]
    }
    _ -> [vxml]
  }
}

fn nodemap_factory(inner: InnerParam) -> n2t.OneToManyNoErrorNodeMap {
  nodemap(_, inner)
}

fn transform_factory(inner: InnerParam) -> DesugarerTransform {
  nodemap_factory(inner)
  |> n2t.one_to_many_no_error_nodemap_2_desugarer_transform_with_forbidden(["MathBlock", "Math"])
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(param)
}

type Param = String
//           ↖
//           local path
//           of source

type InnerParam = Param

pub const name = "break_lines_into_span_tooltips"

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
                    \"some text\"
                ",
      expected: "
                <> root
                  <> span
                    <> span
                      class=tooltip-3003-container
                      <> span
                        class=tooltip-3003-text
                        <>
                          \"some text\"
                      <> span
                        class=tooltip-3003
                        onClick=sendCmdTo3003('code --goto ../path/to/content/tst.source:3:50');
                        <>
                          \"../path/to/content/tst.source:3:50\"
                "
    ),
  ]
}

pub fn assertive_tests() {
  infra.assertive_test_collection_from_data(name, assertive_tests_data(), constructor)
}