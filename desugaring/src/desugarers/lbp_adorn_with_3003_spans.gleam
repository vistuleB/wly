import gleam/option
import gleam/list
import gleam/string.{inspect as ins}
import infrastructure.{ type Desugarer, Desugarer, type DesugarerTransform, type DesugaringError } as infra
import nodemaps_2_desugarer_transforms as n2t
import vxml.{ type VXML, type Attr, Attr, Line, T, V }
import blame as bl

const b = bl.Des([], name, 14)

fn nodemap(
  vxml: VXML,
  inner: InnerParam,
) -> VXML {
  case vxml {
    V(blame, tag, _, children) -> {
      case list.contains(inner.2, tag), blame {
        True, bl.Src(..) -> {
          let span = V(b, "span", inner.3, [ T(b, [ Line(b, inner.0 <> bl.blame_digest(blame)) ]) ])
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

fn transform_factory(inner: InnerParam) -> DesugarerTransform {
  nodemap_factory(inner)
  |> n2t.one_to_one_no_error_nodemap_2_desugarer_transform()
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  let span_class = case param.1 { "" -> "t-3003" _ -> "t-3003 " <> param.1 }
  let attrs = [Attr(b, "class", span_class)]
  Ok(#(param.0, param.1, param.2, attrs))
}

type Param = #(String,      String,         List(String))
//             ↖            ↖               ↖
//             local path   additional      tags to add 3003
//             of source    class, if any   span to
type InnerParam = #(String, String, List(String), List(Attr))

pub const name = "lbp_adorn_with_3003_spans"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
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
    infra.AssertiveTestData(
      param: #("./wly/", "sum_class", ["MathBlock"]),
      source:   "
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
  infra.assertive_test_collection_from_data(name, assertive_tests_data(), constructor)
}
