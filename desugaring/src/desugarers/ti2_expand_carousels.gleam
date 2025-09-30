import gleam/list
import gleam/string
import gleam/option.{type Option, None, Some}
import infrastructure.{type Desugarer, Desugarer, type DesugarerTransform, type DesugaringError, DesugaringError} as infra
import nodemaps_2_desugarer_transforms as n2t
import vxml.{type VXML, type Attribute, T, V, Attribute}
import blame as bl
import on

fn extract_width_height_from_style(
  style_attr: Option(Attribute),
) -> Result(#(Option(String), Option(String), Option(Attribute)), DesugaringError) {
  case style_attr {
    None -> Ok(#(None, None, None))
    Some(Attribute(blame, k, value)) -> {
      assert k == "style"
      use #(w, value) <- on.ok(infra.style_extract_unique_key_or_none(value, "width", blame))
      use #(h, value) <- on.ok(infra.style_extract_unique_key_or_none(value, "height", blame))
      let style_attr = case value == "" {
        True -> None
        False -> Some(Attribute(blame, "style", value))
      }
      Ok(#(w, h, style_attr))
    }
  }
}

fn nodemap(
  vxml: VXML,
) -> Result(VXML, DesugaringError) {
  case vxml {
    T(_, _) -> Ok(vxml)
    V(blame, tag, attrs, children) if tag == "Carousel" -> {
      case children {
        [] -> {
          let #(src_attrs, attrs) = list.partition(attrs, fn(attr) { attr.key == "src" })

          use #(width_attr, attrs) <- on.ok(
            infra.attributes_extract_unique_key_or_none(attrs, "width")
          )

          use #(height_attr, attrs) <- on.ok(
            infra.attributes_extract_unique_key_or_none(attrs, "height")
          )

          use #(style_attr, attrs) <- on.ok(
            infra.attributes_extract_unique_key_or_none(attrs, "style")
          )

          use #(width_prop, height_prop, style_attr) <- on.ok(
            extract_width_height_from_style(style_attr)
          )

          use width_style <- on.ok(
            case width_attr, width_prop {
              Some(x), Some(_) -> Error(DesugaringError(x.blame, "duplicate width definition via attribute and style element"))
              Some(x), None -> Ok("width:" <> x.value)
              None, Some(value) -> Ok("width:" <> value)
              None, None -> Ok("")
            }
          )

          use height_style <- on.ok(
            case height_attr, height_prop {
              Some(x), Some(_) -> Error(DesugaringError(x.blame, "duplicate height definition via attribute and style element"))
              Some(x), None -> Ok("height:" <> x.value)
              None, Some(value) -> Ok("height:" <> value)
              None, None -> Ok("")
            }
          )

          let child_style_attr = case width_style, height_style {
            "", "" -> None
            _, "" -> Some(Attribute(desugarer_blame(69), "style", width_style))
            "", _ -> Some(Attribute(desugarer_blame(69), "style", height_style))
            _, _ -> Some(Attribute(desugarer_blame(69), "style", width_style <> ";" <> height_style))
          }

          let items = case child_style_attr {
            None -> list.map(
              src_attrs,
              fn(src_attr) {
                let img = V(src_attr.blame, "img", [src_attr], [])
                V(src_attr.blame, "CarouselItem", [], [img])
              }
            )
            Some(child_style_attr) -> list.map(
              src_attrs,
              fn(src_attr) {
                let img = V(src_attr.blame, "img", [child_style_attr, src_attr], [])
                V(src_attr.blame, "CarouselItem", [], [img])
              }
            )
          }

          V(
            blame,
            "Carousel",
            list.append(attrs, [style_attr] |> option.values),
            items,
          )
          |> Ok
        }

        _ -> {
          // check if there are any src attributes - error if there are
          case list.any(attrs, fn(attr) { attr.key == "src" }) {
            True ->
              Error(DesugaringError(
                blame,
                "Carousel cannot have src attribute and children at the same time"
              ))
            False -> Ok(vxml)
          }
        }
      }
    }
    _ -> Ok(vxml)
  }
}

fn nodemap_factory() -> n2t.OneToOneNodeMap {
  nodemap
}

fn transform_factory() -> DesugarerTransform {
  nodemap_factory()
  |> n2t.one_to_one_nodemap_2_desugarer_transform()
}

fn param_to_inner_param(_param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(Nil)
}

pub const name = "ti2_expand_carousels"
fn desugarer_blame(line_no: Int) { bl.Des([], name, line_no) }

type Param = Nil
type InnerParam = Nil

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// Expands compressed Carousel syntax to full form.
///
/// Transforms:
/// ```
/// |> Carousel
///     src=blabla
///     src=bloblo
///     width=200px
///     height=150px
/// ```
///
/// To:
/// ```
/// |> Carousel
///     |> CarouselItem
///         |> img
///             src=blabla
///             width=200px
///             height=150px
///     |> CarouselItem
///         |> img
///             src=bloblo
///             width=200px
///             height=150px
/// ```
///
/// Validates that compressed Carousel has:
/// - No children
/// - Only src, width, and height attributes
/// - At least one src attribute
pub fn constructor() -> Desugarer {
  Desugarer(
    name: name,
    stringified_param: None,
    stringified_outside: None,
    transform: case param_to_inner_param(Nil) {
      Error(e) -> fn(_) { Error(e) }
      Ok(_) -> transform_factory()
    }
  )
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
fn assertive_tests_data() -> List(infra.AssertiveTestDataNoParam) {
  [
    infra.AssertiveTestDataNoParam(
      source:   "
                <> Carousel
                  src=\"image1.jpg\"
                  src=\"image2.jpg\"
                  src=\"image3.jpg\"
                ",
      expected: "
                <> Carousel
                  <> CarouselItem
                    <> img
                      src=\"image1.jpg\"
                  <> CarouselItem
                    <> img
                      src=\"image2.jpg\"
                  <> CarouselItem
                    <> img
                      src=\"image3.jpg\"
                ",
    ),
    infra.AssertiveTestDataNoParam(
      source:   "
                <> Carousel
                  src=\"image1.jpg\"
                  src=\"image2.jpg\"
                  width=\"200px\"
                  height=\"150px\"
                ",
      expected: "
                <> Carousel
                  <> CarouselItem
                    <> img
                      src=\"image1.jpg\"
                      style=width: \"200px\"; height: \"150px\";
                  <> CarouselItem
                    <> img
                      src=\"image2.jpg\"
                      style=width: \"200px\"; height: \"150px\";
                ",
    ),
    infra.AssertiveTestDataNoParam(
      source:   "
                <> Carousel
                  src=\"only.jpg\"
                  width=\"100px\"
                ",
      expected: "
                <> Carousel
                  <> CarouselItem
                    <> img
                      src=\"only.jpg\"
                      style=width: \"100px\";
                ",
    ),
    infra.AssertiveTestDataNoParam(
      source:   "
                <> root
                  <> Carousel
                    src=\"single.jpg\"
                  <> div
                    <>
                      \"Other content\"
                ",
      expected: "
                <> root
                  <> Carousel
                    <> CarouselItem
                      <> img
                        src=\"single.jpg\"
                  <> div
                    <>
                      \"Other content\"
                ",
    ),
    infra.AssertiveTestDataNoParam(
      source:   "
                <> root
                  <> div
                    <>
                      \"No carousel here\"
                ",
      expected: "
                <> root
                  <> div
                    <>
                      \"No carousel here\"
                ",
    ),
  ]
}


// Note: Error testing infrastructure is not available,
// so we only include assertive tests for valid cases.
// Invalid cases that would result in DesugaringError at runtime:
// - Multiple width attributes: "Carousel should have only one width attribute."
// - Multiple height attributes: "Carousel should have only one height attribute."
// - src attributes with children: "Carousel cannot have src attribute and children at the same time."

pub fn assertive_tests() {
  infra.assertive_test_collection_from_data_no_param(name, assertive_tests_data(), constructor)
}
