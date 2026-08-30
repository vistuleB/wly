import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
}
import desugaring/nodemaps_2_transform as n2t
import gleam/list
import vxml.{type Attr, type VXML, Attr, Line, T, V}
import vxml/blame as bl

pub const name = "ti2_wrap_with_3003_spans"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Wraps configured source-backed elements in tooltip
/// spans containing source locations resolved by the 3003
/// helper process, not by the browser.
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
    // Prefix prepended to the source-blame path. A relative
    // prefix is relative to the working directory of the
    // 3003 helper process, normally the project root.
    String,
    // Additional tooltip class, or an empty string.
    String,
    // Element names to wrap.
    List(String),
  )

type InnerParam {
  InnerParam(
    source_path_prefix: String,
    additional_class: String,
    target_tags: List(String),
    inner_span_attrs: List(Attr),
    outer_span_attrs: List(Attr),
  )
}

const b = bl.Des([], name, 40)

fn nodemap(vxml: VXML, inner: InnerParam) -> VXML {
  case vxml {
    V(blame, tag, _, _) -> {
      case list.contains(inner.target_tags, tag), blame {
        True, bl.Src(..) -> {
          let inner_span =
            V(b, "span", inner.inner_span_attrs, [
              T(b, [
                Line(b, inner.source_path_prefix <> bl.blame_digest(blame)),
              ]),
            ])
          let outer_span =
            V(b, "span", inner.outer_span_attrs, [vxml, inner_span])
          outer_span
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
  let inner_span_class = case param.1 {
    "" -> "t-3003"
    _ -> "t-3003 " <> param.1
  }
  let inner_span_attrs = [Attr(b, "class", inner_span_class)]
  let outer_span_attrs = [Attr(b, "class", "t-3003-c")]
  Ok(InnerParam(param.0, param.1, param.2, inner_span_attrs, outer_span_attrs))
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
fn assertive_tests_data() -> List(core.AssertiveTestData(Param)) {
  [
    core.AssertiveTestData(
      param: #("./wly/", "sum_class", ["Math"]),
      source: "
                <> root
                  <> Math
                    <>
                      'a+b'
                ",
      expected: "
                <> root
                  <> span
                    class=t-3003-c
                    <> Math
                      <>
                        'a+b'
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
