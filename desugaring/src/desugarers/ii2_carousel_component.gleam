import gleam/option
import gleam/string.{inspect as ins}
import infrastructure.{type Desugarer, Desugarer, type DesugarerTransform, type DesugaringError} as infra
import nodemaps_2_desugarer_transforms as n2t
import vxml.{type VXML, T, V}
import on

fn nodemap(
  vxml: VXML,
) -> Result(VXML, DesugaringError) {
  case vxml {
    V(blame, _, _, _) -> {
      // remove carousel buttons
      use <- on.true_false(
        infra.v_has_key_val(vxml, "data-slide", "prev"),
        on_true: fn() { Ok(T(blame, [])) },
      )
      use <- on.true_false(
        infra.v_has_key_val(vxml, "data-slide", "next"),
        on_true: fn() { Ok(T(blame, [])) },
      )
      use <- on.true_false(
        infra.v_first_attr_with_key(vxml, "data-slide-to") |> option.is_some,
        on_true: fn() { Ok(T(blame, [])) },
      )
      // carousel
      use <- on.true_false(
        !{ infra.v_has_key_val(vxml, "class", "carousel") },
        on_true: fn() { Ok(vxml) },
      )
      // vxml is node with carousel class
      // get only images from children
      let images = infra.descendants_with_tag(vxml, "img")
      let attrs = case infra.v_has_key_val(vxml, "id", "cyk-demo") {
        True -> [vxml.Attr(blame, "jumpToLast", "true")]
        False -> []
      }
      let carousel_node = V(blame, "Carousel", attrs, images)
      Ok(carousel_node)
    }
    _ -> Ok(vxml)
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

pub const name = "ii2_carousel_component"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// converts Bootstrap carousel components to custom
/// Carousel components
pub fn constructor(param: Param) -> Desugarer {
  Desugarer(
    name: name,
    stringified_param: option.Some(ins(Nil)),
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
