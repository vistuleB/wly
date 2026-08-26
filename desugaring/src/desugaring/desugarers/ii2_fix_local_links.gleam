import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
}
import desugaring/nodemaps_2_transform as n2t
import gleam/list
import gleam/string
import on
import vxml.{type VXML, T, V}

fn nodemap(vxml: VXML) -> Result(VXML, DesugaringError) {
  case vxml {
    V(blame, tag, attrs, children) -> {
      use href <- on.none_some(core.v_first_attr_with_key(vxml, "href"), fn() {
        Ok(vxml)
      })
      use <- on.false_true(string.starts_with(href.val, "../../demo"), fn() {
        Ok(vxml)
      })
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

fn inner_param_to_transform(_: InnerParam) -> DesugarerTransform {
  let nodemap: n2t.OneToOneNodemap = nodemap
  n2t.one_to_one_nodemap_2_desugarer_transform(nodemap)
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(param)
}

type Param =
  Nil

type InnerParam =
  Nil

pub const name = "ii2_fix_local_links"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
/// Converts relative links in II2 content to the absolute
/// URLs expected by the published site.
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
  []
}

pub fn assertive_tests() {
  core.assertive_test_collection_from_data(
    name,
    assertive_tests_data(),
    constructor,
  )
}
