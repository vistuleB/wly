import gleam/option.{Some}
import gleam/string.{inspect as ins}
import infrastructure.{ type Desugarer, Desugarer, type DesugarerTransform, type DesugaringError } as infra
import nodemaps_2_desugarer_transforms as n2t
import vxml.{ type VXML, Attr, Line, T, V }
import blame as bl

// remember to replace these names in tests,
// as well:
const tooltip_classname = "t-3003 t-3003-i"
const b = bl.Des([], name, 14)

fn nodemap(
  vxml: VXML,
  inner: InnerParam,
) -> List(VXML) {
  case vxml {
    V(_, "img", attrs, _) -> {
      let assert Some(src) = infra.attrs_val_of_first_with_key(attrs, "src")
      let span = V(
        b,
        "span",
        [ Attr(b, "class", tooltip_classname) ],
        [ T(b, [Line(b, inner <> src)]) ],
      )
      [vxml, span]
    }
    _ -> [vxml]
  }
}

fn nodemap_factory(inner: InnerParam) -> n2t.OneToManyNoErrorNodeMap {
  nodemap(_, inner)
}

fn transform_factory(inner: InnerParam, outside: List(String)) -> DesugarerTransform {
  nodemap_factory(inner)
  |> n2t.one_to_many_no_error_nodemap_2_desugarer_transform_with_forbidden(outside)
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(param)
}

type Param = String
//           ↖
//           local path
//           of source
type InnerParam = Param

pub const name = "ti2_adorn_img_with_3003_spans"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// add a <span class=t-3003 t-3003-i>...</span>
/// after each img containing
pub fn constructor(param: Param, outside: List(String)) -> Desugarer {
  Desugarer(
    name: name,
    stringified_param: option.Some(ins(param)),
    stringified_outside: option.None,
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
      param: "./public/",
      outside: [],
      source:   "
                          <> root
                            <> img
                              src=img/hello.svg
                ",
      expected: "
                          <> root
                            <> img
                              src=img/hello.svg
                            <> span
                              class=t-3003 t-3003-i
                              <>
                                './public/img/hello.svg'
                "
    ),
  ]
}

pub fn assertive_tests() {
  infra.assertive_test_collection_from_data_with_outside(name, assertive_tests_data(), constructor)
}
