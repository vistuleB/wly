import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
}
import desugaring/nodemaps_2_transform as n2t
import gleam/list
import vxml.{type Attr, type VXML, Attr, Line, T, V}
import vxml/blame as bl

pub const name = "lbp_wrap_with_3003_spans"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Wraps configured LBP elements in the nested spans used by
/// the 3003 source-location interface.
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
    // Local path of the source document.
    String,
    // Additional class, if any.
    String,
    // Element names to wrap in 3003 spans.
    List(String),
  )

type InnerParam =
  #(String, String, List(String), List(Attr), List(Attr))

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  let inner_span_class = case param.1 {
    "" -> "t-3003"
    _ -> "t-3003 " <> param.1
  }
  let inner_span_attrs = [Attr(b, "class", inner_span_class)]
  let outer_span_attrs = [Attr(b, "class", "t-3003-c")]
  Ok(#(param.0, param.1, param.2, inner_span_attrs, outer_span_attrs))
}

fn inner_param_to_transform(inner: InnerParam) -> DesugarerTransform {
  nodemap_factory(inner)
  |> n2t.one_to_one_no_error_nodemap_2_desugarer_transform()
}

fn nodemap_factory(inner: InnerParam) -> n2t.OneToOneNoErrorNodemap {
  nodemap(_, inner)
}

fn nodemap(vxml: VXML, inner: InnerParam) -> VXML {
  case vxml {
    V(blame, tag, _, _) -> {
      case list.contains(inner.2, tag), blame {
        True, bl.Src(..) -> {
          let inner_span =
            V(b, "span", inner.3, [
              T(b, [Line(b, inner.0 <> bl.blame_digest(blame))]),
            ])
          let outer_span = V(b, "span", inner.4, [vxml, inner_span])
          outer_span
        }
        _, _ -> vxml
      }
    }
    _ -> vxml
  }
}

const b = bl.Des([], name, 78)

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
