import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
}
import desugaring/nodemaps_2_transform as n2t
import gleam/option
import on
import vxml.{type VXML, T, V}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(param)
}

fn inner_param_to_transform(_: InnerParam) -> DesugarerTransform {
  let nodemap: n2t.OneToOneNodemap = nodemap
  n2t.one_to_one_nodemap_2_desugarer_transform(nodemap)
}

fn nodemap(vxml: VXML) -> Result(VXML, DesugaringError) {
  case vxml {
    V(blame, _, _, _) -> {
      // remove carousel buttons
      use <- on.true_false(
        core.v_has_key_val(vxml, "data-slide", "prev"),
        on_true: fn() { Ok(T(blame, [])) },
      )
      use <- on.true_false(
        core.v_has_key_val(vxml, "data-slide", "next"),
        on_true: fn() { Ok(T(blame, [])) },
      )
      use <- on.true_false(
        core.v_first_attr_with_key(vxml, "data-slide-to") |> option.is_some,
        on_true: fn() { Ok(T(blame, [])) },
      )
      // carousel
      use <- on.true_false(
        !{ core.v_has_key_val(vxml, "class", "carousel") },
        on_true: fn() { Ok(vxml) },
      )
      // vxml is node with carousel class
      // get only images from children
      let images = core.descendants_with_tag(vxml, "img")
      let attrs = case core.v_has_key_val(vxml, "id", "cyk-demo") {
        True -> [vxml.Attr(blame, "jumpToLast", "true")]
        False -> []
      }
      let carousel_node = V(blame, "Carousel", attrs, images)
      Ok(carousel_node)
    }
    _ -> Ok(vxml)
  }
}

type Param =
  Nil

type InnerParam =
  Nil

pub const name = "ii2_carousel_component"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
/// Converts Bootstrap carousel markup into the custom
/// `Carousel` component structure used by II2.
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
