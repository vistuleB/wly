import on
import gleam/list
import gleam/option.{type Option, Some, None}
import gleam/string.{inspect as ins}
import infrastructure.{ type Desugarer, Desugarer, type DesugarerTransform, type DesugaringError } as infra
import nodemaps_2_desugarer_transforms as n2t
import vxml.{ type VXML, Attr, Line, T, V }
import blame as bl

// remember to replace these names in tests,
// as well:
const tooltip_classname = "t-3003 t-3003-i"
const b = bl.Des([], name, 14)

fn v_before(
  vxml: VXML,
  state: State
) ->  Result(#(VXML, State), DesugaringError) {
  let tags = ["img", "figure", "Carousel"]
  let attr = "original"
  case vxml {
    V(blame, tag, _, _) as v -> case list.contains(tags, tag) && infra.v_has_attr_with_key(v, attr) {
      True -> {
        case state {
          Some(_) -> Error(infra.DesugaringError(bl.Des([], name, 44), "The state has already been set, which shouldn't happen"))
          None -> {
            use url <- on.lazy_none_some(
              infra.v_val_of_first_attr_with_key(v, attr),
              fn() { Error(infra.DesugaringError(blame, "Value of attribute \"original\" missing")) }
            )
            Ok(#(vxml, Some(url)))
          }
        }
      }
      False -> Ok(#(vxml, state))
    }
    _ -> Ok(#(vxml, state))
  }
}

fn span_url(inner: InnerParam, path: String) -> VXML {
  V(b, "span", [Attr(b, "class", "t-3003-i-url")], [ T(b, [Line(b, inner <> path)]) ])
}

fn v_after(
  vxml: VXML,
  inner: InnerParam,
  original_state: State,
  latest_state: State,
) -> Result(#(List(VXML), State), DesugaringError) {
  case vxml {
    V(_, "img", attrs, _) -> {
      let assert Some(src) = infra.attrs_val_of_first_with_key(attrs, "src")
      case latest_state {
        None -> {
          let span = V(
                  b,
                  "span",
                  [ Attr(b, "class", tooltip_classname) ],
                  [ span_url(inner, src)],
                )
          Ok(#([vxml, span], original_state))
        }
        Some(original_src) -> {
          let br = V(b, "br", [], [])
          let span = V(
            b,
            "span",
            [ Attr(b, "class", tooltip_classname) ],
            [
              span_url(inner, original_src),
              br,
              span_url(inner, src),
            ],
          )
          Ok(#([vxml, span], original_state))
        }
      }
    }
    _ -> Ok(#([vxml], original_state))
  }
}

fn nodemap_factory(inner: InnerParam) -> n2t.OneToManyBeforeAndAfterStatefulNodeMap(State) {
  n2t.OneToManyBeforeAndAfterStatefulNodeMap(
    v_before_transforming_children: v_before,
    v_after_transforming_children: fn(vxml, original_state, latest_state) { v_after(vxml, inner, original_state, latest_state)  },
    t_nodemap: fn(vxml, _) { Ok(#([vxml], None)) }
  )
}

fn transform_factory(inner: InnerParam) -> DesugarerTransform {
  nodemap_factory(inner)
  |> n2t.one_to_many_before_and_after_stateful_nodemap_2_desugarer_transform(None)
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(param)
}

type State = Option(String)
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
pub fn constructor(param: Param, _outside: List(String)) -> Desugarer {
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
                              <> span
                                class=t-3003-i-url
                                <>
                                  './public/img/hello.svg'
                "
    ),
    infra.AssertiveTestDataWithOutside(
      param: "./assets/",
      outside: [],
      source:   "
                          <> root
                            <> img
                              src=img/compressed.jpg
                              original=img/original.jpg
                ",
      expected: "
                          <> root
                            <> img
                              src=img/compressed.jpg
                              original=img/original.jpg
                            <> span
                              class=t-3003 t-3003-i
                              <> span
                                class=t-3003-i-url
                                <>
                                  './assets/img/original.jpg'
                              <> br
                              <> span
                                class=t-3003-i-url
                                <>
                                  './assets/img/compressed.jpg'
                "
    ),
    infra.AssertiveTestDataWithOutside(
      param: "/media/",
      outside: [],
      source:   "
                          <> root
                            <> figure
                              original=photos/fullsize.png
                              <> img
                                src=photos/thumb.png
                ",
      expected: "
                          <> root
                            <> figure
                              original=photos/fullsize.png
                              <> img
                                src=photos/thumb.png
                              <> span
                                class=t-3003 t-3003-i
                                <> span
                                  class=t-3003-i-url
                                  <>
                                    '/media/photos/fullsize.png'
                                <> br
                                <> span
                                  class=t-3003-i-url
                                  <>
                                    '/media/photos/thumb.png'
                "
    ),
    infra.AssertiveTestDataWithOutside(
      param: "./static/",
      outside: [],
      source:   "
                          <> root
                            <> Carousel
                              original=carousel/slide-hq.webp
                              <> img
                                src=carousel/slide.webp
                ",
      expected: "
                          <> root
                            <> Carousel
                              original=carousel/slide-hq.webp
                              <> img
                                src=carousel/slide.webp
                              <> span
                                class=t-3003 t-3003-i
                                <> span
                                  class=t-3003-i-url
                                  <>
                                    './static/carousel/slide-hq.webp'
                                <> br
                                <> span
                                  class=t-3003-i-url
                                  <>
                                    './static/carousel/slide.webp'
                "
    ),
    infra.AssertiveTestDataWithOutside(
      param: "./public/",
      outside: [],
      source:   "
                          <> root
                            <> img
                              src=img/logo.svg
                            <> img
                              src=img/banner.jpg
                              original=img/banner-original.jpg
                            <> figure
                              original=img/photo-hires.png
                              <> img
                                src=img/photo.png
                ",
      expected: "
                          <> root
                            <> img
                              src=img/logo.svg
                            <> span
                              class=t-3003 t-3003-i
                              <> span
                                class=t-3003-i-url
                                <>
                                  './public/img/logo.svg'
                            <> img
                              src=img/banner.jpg
                              original=img/banner-original.jpg
                            <> span
                              class=t-3003 t-3003-i
                              <> span
                                class=t-3003-i-url
                                <>
                                  './public/img/banner-original.jpg'
                              <> br
                              <> span
                                class=t-3003-i-url
                                <>
                                  './public/img/banner.jpg'
                            <> figure
                              original=img/photo-hires.png
                              <> img
                                src=img/photo.png
                              <> span
                                class=t-3003 t-3003-i
                                <> span
                                  class=t-3003-i-url
                                  <>
                                    './public/img/photo-hires.png'
                                <> br
                                <> span
                                  class=t-3003-i-url
                                  <>
                                    './public/img/photo.png'
                "
    ),
    infra.AssertiveTestDataWithOutside(
      param: "../images/",
      outside: [],
      source:   "
                          <> root
                            <> img
                              src=gallery/thumbnail.jpg
                              original=gallery/full-resolution.jpg
                ",
      expected: "
                          <> root
                            <> img
                              src=gallery/thumbnail.jpg
                              original=gallery/full-resolution.jpg
                            <> span
                              class=t-3003 t-3003-i
                              <> span
                                class=t-3003-i-url
                                <>
                                  '../images/gallery/full-resolution.jpg'
                              <> br
                              <> span
                                class=t-3003-i-url
                                <>
                                  '../images/gallery/thumbnail.jpg'
                "
    ),
    // Test case - Multiple nested structures
    infra.AssertiveTestDataWithOutside(
      param: "./public/",
      outside: [],
      source:   "
                          <> root
                            <> figure
                              original=diagrams/chart-hires.svg
                              <> img
                                src=diagrams/chart.svg
                            <> Carousel
                              original=gallery/slide-full.jpg
                              <> img
                                src=gallery/slide-thumb.jpg
                ",
      expected: "
                          <> root
                            <> figure
                              original=diagrams/chart-hires.svg
                              <> img
                                src=diagrams/chart.svg
                              <> span
                                class=t-3003 t-3003-i
                                <> span
                                  class=t-3003-i-url
                                  <>
                                    './public/diagrams/chart-hires.svg'
                                <> br
                                <> span
                                  class=t-3003-i-url
                                  <>
                                    './public/diagrams/chart.svg'
                            <> Carousel
                              original=gallery/slide-full.jpg
                              <> img
                                src=gallery/slide-thumb.jpg
                              <> span
                                class=t-3003 t-3003-i
                                <> span
                                  class=t-3003-i-url
                                  <>
                                    './public/gallery/slide-full.jpg'
                                <> br
                                <> span
                                  class=t-3003-i-url
                                  <>
                                    './public/gallery/slide-thumb.jpg'
                "
    ),
  ]
}

pub fn assertive_tests() {
  infra.assertive_test_collection_from_data_with_outside(name, assertive_tests_data(), constructor)
}
