import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError, DesugaringError,
}
import desugaring/nodemaps_2_transform as n2t
import gleam/list
import gleam/option.{None, Some}
import on
import vxml.{type VXML, Attr, V}
import vxml/blame as bl

pub const name = "ti2_expand_carousels"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Expands compact Carousel attributes into CarouselItem
/// elements containing images.
pub fn constructor() -> Desugarer {
  authoring.no_param_desugarer(
    name: name,
    transform: inner_param_to_transform(),
  )
}

fn inner_param_to_transform() -> DesugarerTransform {
  let nodemap: n2t.OneToOneNodemap = nodemap
  nodemap
  |> n2t.one_to_one_nodemap_2_desugarer_transform()
}

fn nodemap(vxml: VXML) -> Result(VXML, DesugaringError) {
  case vxml {
    V(blame, tag, attrs, children) if tag == "Carousel" -> {
      case children {
        [] -> {
          let #(src_attrs, attrs) =
            core.attrs_extract_key_occurrences(attrs, "src")

          use #(width_attr, attrs) <- on.ok(
            core.attrs_extract_unique_key_or_none(attrs, "width"),
          )

          use #(height_attr, attrs) <- on.ok(
            core.attrs_extract_unique_key_or_none(attrs, "height"),
          )

          use #(style_attr, attrs) <- on.ok(
            core.attrs_extract_unique_key_or_none(attrs, "style"),
          )

          use #(width_style, style_attr) <- on.ok(
            core.optional_style_extract_unique_key_or_none(style_attr, "width"),
          )

          use #(height_style, style_attr) <- on.ok(
            core.optional_style_extract_unique_key_or_none(style_attr, "height"),
          )

          use width_style <- on.ok(case width_attr, width_style {
            Some(attr), Some(_) ->
              Error(DesugaringError(
                attr.blame,
                "duplicate width definition via attr and style element",
              ))
            Some(attr), None -> Ok("width:" <> attr.val)
            None, Some(x) -> Ok("width:" <> x)
            None, None -> Ok("")
          })

          use height_style <- on.ok(case height_attr, height_style {
            Some(attr), Some(_) ->
              Error(DesugaringError(
                attr.blame,
                "duplicate height definition via attr and style element",
              ))
            Some(attr), None -> Ok("height:" <> attr.val)
            None, Some(x) -> Ok("height:" <> x)
            None, None -> Ok("")
          })

          let item_style_attr = case width_style, height_style {
            "", "" -> None
            _, "" -> Some(Attr(desugarer_blame(79), "style", width_style))
            "", _ -> Some(Attr(desugarer_blame(80), "style", height_style))
            _, _ ->
              Some(Attr(
                desugarer_blame(83),
                "style",
                width_style <> ";" <> height_style,
              ))
          }

          let items = case item_style_attr {
            None ->
              list.map(src_attrs, fn(src_attr) {
                let img = V(src_attr.blame, "img", [src_attr], [])
                V(src_attr.blame, "CarouselItem", [], [img])
              })

            Some(item_style_attr) ->
              list.map(src_attrs, fn(src_attr) {
                let img =
                  V(src_attr.blame, "img", [item_style_attr, src_attr], [])
                V(src_attr.blame, "CarouselItem", [], [img])
              })
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
                "Carousel cannot have src attr and children at the same time",
              ))
            False -> Ok(vxml)
          }
        }
      }
    }

    _ -> Ok(vxml)
  }
}

fn desugarer_blame(line_no: Int) {
  bl.Des([], name, line_no)
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
fn assertive_tests_data() -> List(core.AssertiveTestDataNoParam) {
  [
    core.AssertiveTestDataNoParam(
      source: "
                          <> Carousel
                            src=image1.jpg
                            src=image2.jpg
                            src=image3.jpg
                ",
      expected: "
                          <> Carousel
                            <> CarouselItem
                              <> img
                                src=image1.jpg
                            <> CarouselItem
                              <> img
                                src=image2.jpg
                            <> CarouselItem
                              <> img
                                src=image3.jpg
                ",
    ),
    core.AssertiveTestDataNoParam(
      source: "
                          <> Carousel
                            src=image1.jpg
                            src=image2.jpg
                            width=200px
                            height=150px
                ",
      expected: "
                          <> Carousel
                            <> CarouselItem
                              <> img
                                style=width:200px;height:150px
                                src=image1.jpg
                            <> CarouselItem
                              <> img
                                style=width:200px;height:150px
                                src=image2.jpg
                ",
    ),
    core.AssertiveTestDataNoParam(
      source: "
                          <> Carousel
                            src=only.jpg
                            width=100px
                ",
      expected: "
                          <> Carousel
                            <> CarouselItem
                              <> img
                                style=width:100px
                                src=only.jpg
                ",
    ),
    core.AssertiveTestDataNoParam(
      source: "
                          <> root
                            <> Carousel
                              src=single.jpg
                            <> div
                              <>
                                'Other content'
                ",
      expected: "
                          <> root
                            <> Carousel
                              <> CarouselItem
                                <> img
                                  src=single.jpg
                            <> div
                              <>
                                'Other content'
                ",
    ),
    core.AssertiveTestDataNoParam(
      source: "
                          <> root
                            <> div
                              <>
                                'No carousel here'
                ",
      expected: "
                          <> root
                            <> div
                              <>
                                'No carousel here'
                ",
    ),
  ]
}

// Note: Error testing support is not available,
// so we only include assertive tests for valid cases.
// Invalid cases that would result in DesugaringError at runtime:
// - Multiple width attrs: "Carousel should have only one width attr."
// - Multiple height attrs: "Carousel should have only one height attr."
// - src attrs with children: "Carousel cannot have src attr and children at the same time."

pub fn assertive_tests() {
  core.assertive_test_collection_from_data_no_param(
    name,
    assertive_tests_data(),
    constructor,
  )
}
