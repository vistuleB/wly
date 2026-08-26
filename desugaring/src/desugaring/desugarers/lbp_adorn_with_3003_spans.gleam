import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
}
import desugaring/nodemaps_2_transform as n2t
import gleam/list
import vxml.{type Attr, type VXML, Attr, Line, T, V}
import vxml/blame as bl

const b = bl.Des([], name, 10)

fn nodemap(vxml: VXML, inner: InnerParam) -> VXML {
  case vxml {
    V(blame, tag, _, children) -> {
      case list.contains(inner.2, tag), blame {
        True, bl.Src(..) -> {
          let span =
            V(b, "span", inner.3, [
              T(b, [Line(b, inner.0 <> bl.blame_digest(blame))]),
            ])
          V(..vxml, children: list.append(children, [span]))
        }
        _, _ -> vxml
      }
    }
    _ -> vxml
  }
}

fn nodemap_factory(inner: InnerParam) -> n2t.OneToOneNoErrorNodemap {
  nodemap(_, inner)
}

fn inner_param_to_transform(inner: InnerParam) -> DesugarerTransform {
  nodemap_factory(inner)
  |> n2t.one_to_one_no_error_nodemap_2_desugarer_transform()
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  let span_class = case param.1 {
    "" -> "t-3003"
    _ -> "t-3003 " <> param.1
  }
  let attrs = [Attr(b, "class", span_class)]
  Ok(#(param.0, param.1, param.2, attrs))
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
  #(String, String, List(String), List(Attr))

pub const name = "lbp_adorn_with_3003_spans"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
/// Wraps configured LBP elements in the spans required by
/// the 3003 interface.
pub fn constructor(param: Param) -> Desugarer {
  authoring.desugarer(
    name: name,
    param: param,
    prepare: param_to_inner_param,
    transform: inner_param_to_transform,
  )
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
