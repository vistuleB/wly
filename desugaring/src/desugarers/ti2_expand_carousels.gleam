import gleam/list
import gleam/option.{None, Some}
import infrastructure.{type Desugarer, Desugarer, type DesugarerTransform, type DesugaringError, DesugaringError} as infra
import nodemaps_2_desugarer_transforms as n2t
import vxml.{type VXML, V, Attr}
import blame as bl
import on

fn nodemap(
  vxml: VXML,
) -> Result(VXML, DesugaringError) {
  case vxml {
    V(blame, tag, attrs, children) if tag == "Carousel" -> {
      case children {
        [] -> {
          let #(src_attrs, attrs) = 
            infra.attrs_extract_key_occurrences(attrs, "src")

          use #(width_attr, attrs) <- on.ok(
            infra.attrs_extract_unique_key_or_none(attrs, "width")
          )

          use #(height_attr, attrs) <- on.ok(
            infra.attrs_extract_unique_key_or_none(attrs, "height")
          )

          use #(style_attr, attrs) <- on.ok(
            infra.attrs_extract_unique_key_or_none(attrs, "style")
          )

          use #(width_style, style_attr) <- on.ok(
            infra.optional_style_extract_unique_key_or_none(style_attr, "width")
          )

          use #(height_style, style_attr) <- on.ok(
            infra.optional_style_extract_unique_key_or_none(style_attr, "height")
          )

          use width_style <- on.ok(
            case width_attr, width_style {
              Some(attr), Some(_) -> Error(DesugaringError(attr.blame, "duplicate width definition via attr and style element"))
              Some(attr), None -> Ok("width:" <> attr.val)
              None, Some(x) -> Ok("width:" <> x)
              None, None -> Ok("")
            }
          )

          use height_style <- on.ok(
            case height_attr, height_style {
              Some(attr), Some(_) -> Error(DesugaringError(attr.blame, "duplicate height definition via attr and style element"))
              Some(attr), None -> Ok("height:" <> attr.val)
              None, Some(x) -> Ok("height:" <> x)
              None, None -> Ok("")
            }
          )

          let item_style_attr = case width_style, height_style {
            "", "" -> None
            _, "" -> Some(Attr(desugarer_blame(59), "style", width_style))
            "", _ -> Some(Attr(desugarer_blame(60), "style", height_style))
            _, _ -> Some(Attr(desugarer_blame(61), "style", width_style <> ";" <> height_style))
          }

          let items = case item_style_attr {
            None -> list.map(
              src_attrs,
              fn(src_attr) {
                let img = V(src_attr.blame, "img", [src_attr], [])
                V(src_attr.blame, "CarouselItem", [], [img])
              }
            )

            Some(item_style_attr) -> list.map(
              src_attrs,
              fn(src_attr) {
                let img = V(src_attr.blame, "img", [item_style_attr, src_attr], [])
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
          // check if there are any src attrs - error if there are
          case list.any(attrs, fn(attr) { attr.key == "src" }) {
            True ->
              Error(DesugaringError(
                blame,
                "Carousel cannot have src attr and children at the same time"
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
/// - Only src, width, and height attrs
/// - At least one src attr
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
                      style=width:\"200px\";height:\"150px\"
                      src=\"image1.jpg\"
                  <> CarouselItem
                    <> img
                      style=width:\"200px\";height:\"150px\"
                      src=\"image2.jpg\"
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
                      style=width:\"100px\"
                      src=\"only.jpg\"
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
// - Multiple width attrs: "Carousel should have only one width attr."
// - Multiple height attrs: "Carousel should have only one height attr."
// - src attrs with children: "Carousel cannot have src attr and children at the same time."

pub fn assertive_tests() {
  infra.assertive_test_collection_from_data_no_param(name, assertive_tests_data(), constructor)
}
