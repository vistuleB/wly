import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
}
import desugaring/nodemaps_2_transform as n2t
import gleam/list
import vxml.{type Attr, type VXML, Attr, Line, T, V}
import vxml/blame as bl

pub const name = "ti2_adorn_with_3003_spans"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Appends source-location tooltip spans to configured
/// elements that retain source blame.
pub fn constructor(param: Param) -> Desugarer {
  authoring.desugarer(
    name: name,
    param: param,
    prepare: param_to_inner_param,
    transform: inner_param_to_transform,
  )
}

type Param =
  #(
    // Local path of the source.
    String,
    // Additional tooltip class, or an empty string.
    String,
    // Element names to adorn.
    List(String),
  )

type InnerParam {
  InnerParam(
    source_path: String,
    additional_class: String,
    target_tags: List(String),
    span_attrs: List(Attr),
  )
}

const b = bl.Des([], name, 40)

fn nodemap(vxml: VXML, inner: InnerParam) -> VXML {
  case vxml {
    V(blame, tag, _, children) -> {
      case list.contains(inner.target_tags, tag), blame {
        True, bl.Src(..) -> {
          let span =
            V(b, "span", inner.span_attrs, [
              T(b, [Line(b, inner.source_path <> bl.blame_digest(blame))]),
            ])
          V(..vxml, children: list.append(children, [span]))
        }
        _, _ -> vxml
      }
    }
    _ -> vxml
  }
}

fn inner_param_to_transform(inner: InnerParam) -> DesugarerTransform {
  let nodemap: n2t.OneToOneNoErrorNodemap = nodemap(_, inner)
  nodemap
  |> n2t.one_to_one_no_error_nodemap_2_desugarer_transform()
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  let span_class = case param.1 {
    "" -> "t-3003"
    _ -> "t-3003 " <> param.1
  }
  let attrs = [Attr(b, "class", span_class)]
  Ok(InnerParam(param.0, param.1, param.2, attrs))
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
fn assertive_tests_data() -> List(core.AssertiveTestData(Param)) {
  [
    core.AssertiveTestData(
      param: #("./wly/", "sum_class", ["MathBlock"]),
      source: "
                <> root
                  <> MathBlock
                    <>
                      '$$'
                      'hello'
                      '$$'
                ",
      expected: "
                <> root
                  <> MathBlock
                    <>
                      '$$'
                      'hello'
                      '$$'
                    <> span
                      class=t-3003 sum_class
                      <>
                        './wly/tst.source:2:3 ->'
                ",
    ),
  ]
}

pub fn assertive_tests() {
  core.assertive_test_collection_from_data(
    name,
    assertive_tests_data(),
    constructor,
  )
}
