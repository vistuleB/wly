import gleam/list
import gleam/option
import gleam/string
import desugaring/core.{type Desugarer, Desugarer, type DesugarerTransform, type DesugaringError} as core
import desugaring/nodemaps_2_transform as n2t
import vxml.{type VXML, T, V}
import on

fn nodemap(
  vxml: VXML,
) -> Result(VXML, DesugaringError) {
  case vxml {
    V(blame, tag, attrs, children) -> {
      use href <- on.none_some(
        core.v_first_attr_with_key(vxml, "href"),
        fn() { Ok(vxml) },
      )
      use <- on.false_true(
        string.starts_with(href.val, "../../demo"),
        fn() { Ok(vxml) },
      )
      let attrs =
        attrs
        |> list.map(fn(attr) {
          case attr.key {
            "href" ->
              vxml.Attr(
                attr.blame,
                "href",
                attr.val
                  |> string.replace(
                    "../../demos",
                    "https://www.tu-chemnitz.de/informatik/theoretische-informatik/demos",
                  ),
              )
            _ -> attr
          }
        })
      Ok(V(blame, tag, attrs, children))
    }
    T(_, _) -> Ok(vxml)
  }
}

fn nodemap_factory(_: InnerParam) -> n2t.OneToOneNodemap {
  nodemap
}

fn transform_factory(inner: InnerParam) -> DesugarerTransform {
  n2t.one_to_one_nodemap_2_desugarer_transform(nodemap_factory(inner))
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(param)
}

type Param = Nil
type InnerParam = Nil

pub const name = "ii2_fix_local_links"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// fixes local links in TI2 content by converting
/// relative paths to absolute URLs
pub fn constructor(param: Param) -> Desugarer {
  Desugarer(
    name: name,
    stringified_param: option.None,
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
fn assertive_tests_data() -> List(core.AssertiveTestData(Param)) {
  []
}

pub fn assertive_tests() {
  core.assertive_test_collection_from_data(name, assertive_tests_data(), constructor)
}
