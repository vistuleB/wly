import blame as bl
import infrastructure.{
  type Desugarer,
  type DesugaringError,
  type DesugarerTransform,
  Desugarer,
} as infra
import nodemaps_2_desugarer_transforms as n2t
import gleam/option.{Some, None}
import gleam/string.{inspect as ins}
import vxml.{ type VXML, type Attr, Attr, Line, T, V }

const b = bl.Des([], name, 14)

fn nodemap(
  vxml: VXML,
  inner: InnerParam,
) -> List(VXML) {
  case vxml {
    V(bl.Src(..), "img", _, _) -> {
      case infra.v_val_of_first_attr_with_key(vxml, "src") {
        Some(url) -> {
          let inner_span = V(b, "span", inner.2, [ T(b, [ Line(b, normalize_root_path(inner.0) <> "/" <> normalize_src_path(url)) ]) ])
          let outer_span = V(b, "span", inner.3, [ inner_span ])
          [vxml, outer_span]
        }
        None -> [vxml]
      }
    }
    
    V(bl.Src(..) as blame, "Image", _, _) -> {
      case infra.v_val_of_first_attr_with_key(vxml, "src") {
        Some(url) -> {
          [infra.v_set_attr(vxml, blame, "local_url", normalize_root_path(inner.0) <> "/" <> normalize_src_path(url))]
        }
        None -> [vxml]
      }
    }
    _ -> [vxml]
  }
}

fn normalize_root_path(path: String) -> String {
  case string.ends_with(path, "/") {
    True -> string.drop_end(path, 1)
    False -> path
  }
}

fn normalize_src_path(path: String) -> String {
  case path {
    "./" <> _rest -> string.drop_start(path, 2)
    "/" <> _rest -> string.drop_start(path, 1)
    _ -> path
  }
}

fn nodemap_factory(inner: InnerParam) -> n2t.OneToManyNoErrorNodemap {
  nodemap(_, inner)
}

fn transform_factory(inner: InnerParam) -> DesugarerTransform {
  nodemap_factory(inner)
  |> n2t.one_to_many_no_error_nodemap_2_desugarer_transform()
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  let inner_span_class = case param.1 { "" -> "t-3003-i-url" _ -> "t-3003-i-url " <> param.1 }
  let inner_span_attrs = [Attr(b, "class", inner_span_class)]
  let outer_span_attrs = [Attr(b, "class", "t-3003 t-3003-i")]
  Ok(#(param.0, param.1, inner_span_attrs, outer_span_attrs))
}

type Param = #(String,      String)
//             ↖            ↖              
//             local path   additional      
//             of source    class, if any   
type InnerParam = #(String, String, List(Attr), List(Attr))

pub const name = "lbp_adorn_img_with_3003_spans"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
pub fn constructor(param: Param) -> Desugarer {
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
fn assertive_tests_data() -> List(infra.AssertiveTestData(Param)) {
  [
    infra.AssertiveTestData(
      param: #("./wly/", "sum_class"),
      source:   "
                <> root
                  <> img
                    src=/images/123.svg
                ",
      expected: "
                <> root
                  <> img
                    src=/images/123.svg
                  <> span
                    class=t-3003 t-3003-i
                    <> span
                      class=t-3003-i-url sum_class
                      <>
                        './wly/images/123.svg'
                ",
    ),
  ]
}

pub fn assertive_tests() {
  infra.assertive_test_collection_from_data(name, assertive_tests_data(), constructor)
}
