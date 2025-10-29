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
    V(blame, tag, _, _) -> {
      case list.contains(inner.2, tag), blame {
        True, bl.Src(..) -> {
          let inner_span = V(b, "span", inner.3, [ T(b, [ Line(b, inner.0 <> bl.blame_digest(blame)) ]) ])
          let outer_span = V(b, "span", inner.4, [ vxml, inner_span ])
          outer_span
        }
        _, _ -> vxml
      }
    }
    _ -> vxml
  }
}

fn nodemap_factory(inner: InnerParam) -> n2t.OneToOneNoErrorNodeMap {
  nodemap(_, inner)
}

fn transform_factory(inner: InnerParam) -> DesugarerTransform {
  nodemap_factory(inner)
  |> n2t.one_to_one_no_error_nodemap_2_desugarer_transform()
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  let inner_span_class = case param.1 { "" -> "t-3003" _ -> "t-3003 " <> param.1 }
  let inner_span_attrs = [Attr(b, "class", inner_span_class)]
  let outer_span_attrs = [Attr(b, "class", "t-3003-c")]
  Ok(#(param.0, param.1, param.2, inner_span_attrs, outer_span_attrs))
}

type Param = #(String,      String,         List(String))
//             ↖            ↖               ↖
//             local path   additional      tags to add 3003
//             of source    class, if any   span to
type InnerParam = #(String, String, List(String), List(Attr), List(Attr))

pub const name = "ti2_wrap_with_3003_spans"

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
      param: #("./wly/", "sum_class", ["Math"]),
      source:   "
                <> root
                  <> Math
                    <>
                      \"a+b\"
                ",
      expected: "
                <> root
                  <> span
                    class=t-3003-c
                    <> Math
                      <>
                        \"a+b\"
                    <> span
                      class=t-3003 sum_class
                      <>
                        \"./wly/tst.source:2:3\"
                ",
    ),
  ]
}

pub fn assertive_tests() {
  infra.assertive_test_collection_from_data(name, assertive_tests_data(), constructor)
}