import gleam/result
import on
import gleam/list
import gleam/option.{type Option, Some, None}
import gleam/string.{inspect as ins}
import infrastructure.{
  type Desugarer,
  type DesugarerTransform,
  type DesugaringError,
  DesugaringError,
  Desugarer,
} as infra
import nodemaps_2_desugarer_transforms as n2t
import vxml.{
  type VXML,
  Attr,
  Line,
  T,
  V,
}
import blame.{type Blame} as bl
import filepath

const tooltip_classname = "t-3003 t-3003-i"
const tags = ["img", "figure", "Carousel"]
const original_key = "original"
const b = bl.Des([], name, 27)
const outer_span_attrs = [Attr(b, "class", tooltip_classname)]
const inner_span_attrs = [Attr(b, "class", "t-3003-i-url")]
const br = V(b, "br", [], [])

fn compose_and_simplify_path(
  blame: Blame,
  path: String,
  inner: InnerParam,
) -> Result(String, DesugaringError) {
  filepath.expand(inner <> path)
  |> result.map_error(fn(_) {
    DesugaringError(blame, "path '" <> path <> "' points outside of root directory (?)")
  })
}

fn v_before(
  vxml: VXML,
  state: State,
  inner: InnerParam,
) ->  Result(#(VXML, State), DesugaringError) {
  let assert V(blame, tag, _, _) = vxml
  use <- on.false_true(
    list.contains(tags, tag),
    fn() { Ok(#(vxml, state)) },
  )
  case infra.v_first_attr_with_key(vxml, original_key), state {
    None, _ -> Ok(#(vxml, state))
    Some(attr), None -> {
      use path <- on.ok(compose_and_simplify_path(attr.blame, attr.val, inner))
      Ok(#(vxml, Some(path)))
    }
    Some(_), Some(_) -> {
      Error(DesugaringError(
        blame,
        "descendant attempting to overwrite ancestor '" <> original_key <> "' attribute",
      ))
    }
  }
}

fn inner_span(path: String) -> VXML {
  V(b, "span", inner_span_attrs, [ T(b, [Line(b, path)]) ])
}

fn v_after(
  vxml: VXML,
  inner: InnerParam,
  original_state: State,
  latest_state: State,
) -> Result(#(List(VXML), State), DesugaringError) {
  let assert V(_, tag, attrs, _) = vxml
  use <- on.false_true(
    tag == "img",
    fn() { Ok(#([vxml], original_state)) },
  )
  let assert Some(attr) = infra.attrs_first_with_key(attrs, "src")
  use src <- on.ok(compose_and_simplify_path(attr.blame, attr.val, inner))
  let children = case latest_state {
    None -> [
      inner_span(src)
    ]
    Some(original_src) -> [
      inner_span(original_src),
      br,
      inner_span(src),
    ]
  }
  let outer_span = V(b, "span", outer_span_attrs, children)
  Ok(#([vxml, outer_span], original_state))
}

fn nodemap_factory(inner: InnerParam) -> n2t.OneToManyBeforeAndAfterStatefulNodeMap(State) {
  n2t.OneToManyBeforeAndAfterStatefulNodeMap(
    v_before_transforming_children: fn(vxml, state) { v_before(vxml, state, inner) },
    v_after_transforming_children: fn(vxml, original_state, latest_state) { v_after(vxml, inner, original_state, latest_state) },
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
//           path from exec dir to public
type InnerParam = Param

pub const name = "ti2_adorn_img_with_3003_spans"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
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
                                  'public/img/hello.svg'
                "
    ),
    infra.AssertiveTestDataWithOutside(
      param: "./assets/",
      outside: [],
      source:   "
                          <> root
                            <> img
                              src=img/compressed.jpg
                              original=../img/original.jpg
                ",
      expected: "
                          <> root
                            <> img
                              src=img/compressed.jpg
                              original=../img/original.jpg
                            <> span
                              class=t-3003 t-3003-i
                              <> span
                                class=t-3003-i-url
                                <>
                                  'img/original.jpg'
                              <> br
                              <> span
                                class=t-3003-i-url
                                <>
                                  'assets/img/compressed.jpg'
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
                                    'static/carousel/slide-hq.webp'
                                <> br
                                <> span
                                  class=t-3003-i-url
                                  <>
                                    'static/carousel/slide.webp'
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
                                  'public/img/logo.svg'
                            <> img
                              src=img/banner.jpg
                              original=img/banner-original.jpg
                            <> span
                              class=t-3003 t-3003-i
                              <> span
                                class=t-3003-i-url
                                <>
                                  'public/img/banner-original.jpg'
                              <> br
                              <> span
                                class=t-3003-i-url
                                <>
                                  'public/img/banner.jpg'
                            <> figure
                              original=img/photo-hires.png
                              <> img
                                src=img/photo.png
                              <> span
                                class=t-3003 t-3003-i
                                <> span
                                  class=t-3003-i-url
                                  <>
                                    'public/img/photo-hires.png'
                                <> br
                                <> span
                                  class=t-3003-i-url
                                  <>
                                    'public/img/photo.png'
                "
    ),
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
                                    'public/diagrams/chart-hires.svg'
                                <> br
                                <> span
                                  class=t-3003-i-url
                                  <>
                                    'public/diagrams/chart.svg'
                            <> Carousel
                              original=gallery/slide-full.jpg
                              <> img
                                src=gallery/slide-thumb.jpg
                              <> span
                                class=t-3003 t-3003-i
                                <> span
                                  class=t-3003-i-url
                                  <>
                                    'public/gallery/slide-full.jpg'
                                <> br
                                <> span
                                  class=t-3003-i-url
                                  <>
                                    'public/gallery/slide-thumb.jpg'
                "
    ),
  ]
}

pub fn assertive_tests() {
  infra.assertive_test_collection_from_data_with_outside(name, assertive_tests_data(), constructor)
}
