import gleam/list
import gleam/option
import gleam/string
import infrastructure.{type Desugarer, Desugarer, type DesugarerTransform, type DesugaringError} as infra
import nodemaps_2_desugarer_transforms as n2t
import vxml.{type VXML, T, V}
import on

fn nodemap(
  vxml: VXML,
) -> Result(VXML, DesugaringError) {
  case vxml {
    V(blame, tag, atts, children) -> {
      use href <- on.none_some(
        infra.v_first_attribute_with_key(vxml, "href"),
        Ok(vxml),
      )
      use <- on.false_true(
        string.starts_with(href.value, "../../demo"),
        Ok(vxml),
      )
      let atts =
        atts
        |> list.map(fn(att) {
          case att.key {
            "href" ->
              vxml.Attribute(
                att.blame,
                "href",
                att.value
                  |> string.replace(
                    "../../demos",
                    "https://www.tu-chemnitz.de/informatik/theoretische-informatik/demos",
                  ),
              )
            _ -> att
          }
        })
      Ok(V(blame, tag, atts, children))
    }
    T(_, _) -> Ok(vxml)
  }
}

fn nodemap_factory(_: InnerParam) -> n2t.OneToOneNodeMap {
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

pub const name = "fix_ti2_local_links"

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
fn assertive_tests_data() -> List(infra.AssertiveTestData(Param)) {
  []
}

pub fn assertive_tests() {
  infra.assertive_test_collection_from_data(name, assertive_tests_data(), constructor)
}
