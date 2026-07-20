import gleam/list
import gleam/option
import gleam/string.{inspect as ins}
import infrastructure.{type Desugarer, Desugarer, type DesugarerTransform, type DesugaringError} as infra
import nodemaps_2_desugarer_transforms as n2t
import vxml.{type VXML, Line, T}

// walks a string left-to-right, consuming backslash escapes:
//
//   "\\d"   -> "d"   for d escapable   (escaped delimiter)
//   "\\X"   -> "\\X" otherwise         (left alone)
//
// the second case is what keeps this safe on LaTeX-bearing prose: an
// unrecognized escape is emitted verbatim AND its second character is
// not reconsidered, so "\\alpha" can never lose its backslash.
//
// NOTE a backslash is deliberately NOT self-escapable here: these
// documents use a trailing "\\" as a LaTeX row break in ordinary prose
// (outside any Math node), and collapsing it would corrupt them. The
// cost is that a literal backslash sitting directly in front of a live
// delimiter is not halved -- "\\\\_x_" yields "\\\\<i>x</i>" rather than
// "\\<i>x</i>". No occurrence of that shape exists in any current
// document; fixing it properly means teaching the splitter itself to
// halve the run at the point it consumes it.
fn unescape_graphemes(
  graphemes: List(String),
  escapable: List(String),
  acc: List(String),
) -> String {
  case graphemes {
    [] -> acc |> list.reverse |> string.join("")
    ["\\", second, ..rest] ->
      case list.contains(escapable, second) {
        True -> unescape_graphemes(rest, escapable, [second, ..acc])
        False -> unescape_graphemes(rest, escapable, [second, "\\", ..acc])
      }
    [first, ..rest] -> unescape_graphemes(rest, escapable, [first, ..acc])
  }
}

fn nodemap(node: VXML, inner: InnerParam) -> VXML {
  case node {
    T(blame, lines) ->
      T(
        blame,
        list.map(lines, fn(line) {
          Line(
            line.blame,
            unescape_graphemes(string.to_graphemes(line.content), inner, []),
          )
        }),
      )
    _ -> node
  }
}

fn nodemap_factory(inner: InnerParam) -> n2t.OneToOneNoErrorNodemap {
  nodemap(_, inner)
}

fn transform_factory(inner: InnerParam, outside: List(String)) -> DesugarerTransform {
  nodemap_factory(inner)
  |> n2t.one_to_one_no_error_nodemap_2_desugarer_transform_with_forbidden(outside)
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(param)
}

type Param = List(String)
//           ↖
//           single-character delimiters whose backslash-escape should be
//           consumed, e.g. ["_", "*"]; a backslash is ALWAYS escapable
type InnerParam = Param

pub const name = "unescape_delimiters__outside"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// removes the backslash from escaped delimiters in
/// text nodes, after delimiter splitting has already
/// decided which delimiters were live
///
/// must run AFTER every splitting step, or it would
/// re-arm delimiters that splitting just neutralized
///
/// pass math/code tags in the second argument: inside
/// those a backslash is meaningful to the downstream
/// consumer (MathJax reads "\$" as a literal dollar)
/// and must survive
pub fn constructor(param: Param, outside: List(String)) -> Desugarer {
  Desugarer(
    name: name,
    stringified_param: option.Some(ins(param)),
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
  [
    infra.AssertiveTestDataWithOutside(
      param: ["_", "*"],
      outside: ["Math"],
      source:   "
                <> root
                  <>
                    'a \\_x\\_ b'
                    'a \\* b'
                    'trailing row break stays \\\\'
                    'keep \\alpha and \\frac here'
                  <> Math
                    <>
                      'a \\_x\\_ b'
                ",
      expected: "
                <> root
                  <>
                    'a _x_ b'
                    'a * b'
                    'trailing row break stays \\\\'
                    'keep \\alpha and \\frac here'
                  <> Math
                    <>
                      'a \\_x\\_ b'
                ",
    ),
  ]
}

pub fn assertive_tests() {
  infra.assertive_test_collection_from_data_with_outside(name, assertive_tests_data(), constructor)
}
