import gleam/list
import gleam/option.{type Option, Some, None}
import gleam/string
import infrastructure.{type Desugarer, Desugarer, type DesugaringError, DesugaringError, type DesugarerTransform} as infra
import vxml.{type VXML, type Attr, V}
import nodemaps_2_desugarer_transforms as n2t
import blame.{type Blame}
import on

fn extract_height_width_from_style_and_attrs(
  attrs: List(Attr),
) -> Result(#(String, List(vxml.Attr)), DesugaringError) {
  use #(style_attr, attrs) <- on.ok(
    infra.attrs_extract_unique_key_or_none(attrs, "style")
  )

  use #(width_attr, attrs) <- on.ok(
    infra.attrs_extract_unique_key_or_none(attrs, "width")
  )

  use #(height_attr, attrs) <- on.ok(
    infra.attrs_extract_unique_key_or_none(attrs, "height")
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
      Some(attr), None -> Ok(Some("width:" <> attr.val))
      None, Some(x) -> Ok(Some("width:" <> x))
      None, None -> Ok(None)
    }
  )

  use height_style <- on.ok(
    case height_attr, height_style {
      Some(attr), Some(_) -> Error(DesugaringError(attr.blame, "duplicate height definition via attr and style element"))
      Some(attr), None -> Ok(Some("height:" <> attr.val))
      None, Some(x) -> Ok(Some("height:" <> x))
      None, None -> Ok(None)
    }
  )

  let new_attrs = case style_attr {
    None -> attrs
    Some(attr) -> case string.trim(attr.val) {
      "" -> attrs // remove empty style attribute
      _ -> [attr, ..attrs]
    }
  }

  Ok(#(
    [width_style, height_style]
    |> option.values
    |> string.join(";"),
    new_attrs,
  ))
}

fn merge_new_style_into_state(state: State, blame: Blame, width_height_style: String) -> Result(State, DesugaringError) {
  case state, width_height_style {
    _, "" -> Ok(state)
    None, _ -> Ok(Some(width_height_style))
    Some(x), _ -> Error(DesugaringError(blame, "found overlapping img width-height instructions of ancestor/descendant " <> x <> " " <> width_height_style))
  }
}

fn img_case(
  node: VXML,
  state: State,
) -> Result(#(VXML, State), DesugaringError) {
  let assert V(blame, _, attrs, _) = node

  // could not use 'extract_height_width_from_style_and_attrs'
  // here because it gets very expensive to gratuitously
  // extract from and then reinsert into the 'style' attribute
  // of all img elements; if we wanted to avoid overwriting
  // existing local styles would need an alternate version of
  // 'attrs_merge_prepend_styles' that throws an error when a
  // style property is about to be overwritten

  use #(width_attr, attrs) <- on.ok(
    infra.attrs_extract_unique_key_or_none(attrs, "width")
  )

  use #(height_attr, attrs) <- on.ok(
    infra.attrs_extract_unique_key_or_none(attrs, "height")
  )

  let width_style = width_attr |> option.map(fn(x) {"width:" <> x.val})
  let height_style = height_attr |> option.map(fn(x) {"height:" <> x.val})

  let local_style = 
    [width_style, height_style]
    |> option.values
    |> string.join(";")

  use state <- on.ok(
    merge_new_style_into_state(state, blame, local_style)
  )

  case state {
    None -> Ok(#(node, state))
    Some(width_height_style) -> {
      let attrs = infra.attrs_merge_prepend_styles(attrs, blame, width_height_style)
      Ok(#(V(..node, attrs: attrs), state))
    }
  }
}

fn ancestor_case(
  node: VXML,
  state: State,
) -> Result(#(VXML, State), DesugaringError) {
  let assert V(blame, _, attrs, _) = node
  use #(width_height_style, attrs) <- on.ok(
    extract_height_width_from_style_and_attrs(attrs)
  )
  use state <- on.ok(
    merge_new_style_into_state(state, blame, width_height_style)
  )
  Ok(#(V(..node, attrs: attrs), state))
}

fn v_before_transforming_children(
  node: VXML,
  state: State,
  inner: InnerParam,
) -> Result(#(VXML, State), DesugaringError) {
  let assert V(_, tag, _, _) = node
  case tag {
    "img" -> img_case(node, state)
    _ -> case list.contains(inner, tag) {
      True -> ancestor_case(node, state)
      False -> Ok(#(node, state))
    }
  }
}

fn nodemap_factory(inner: InnerParam) -> n2t.OneToOneBeforeAndAfterStatefulNodeMap(State) {
   n2t.OneToOneBeforeAndAfterStatefulNodeMap(
    v_before_transforming_children: fn(node, state) {
      v_before_transforming_children(node, state, inner)
    },
    v_after_transforming_children:  fn(n, o, _) { Ok(#(n, o)) },
    t_nodemap: fn(n, s) { Ok(#(n, s)) },
  )
}

fn transform_factory(inner: InnerParam) -> DesugarerTransform {
  nodemap_factory(inner)
  |> n2t.one_to_one_before_and_after_stateful_nodemap_2_desugarer_transform(None)
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(param)
}

pub const name = "ti2_cut_paste_width_height_to_descendant_img"

type State = Option(String)
type Param = List(String)
type InnerParam = Param

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// moves height and width styles or attributes from
/// specified tags to descendant img elements.
/// for img elements themselves, moves height/width
/// attributes into the style attribute.
/// empty style attributes are removed after
/// extraction.
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
  [
    infra.AssertiveTestData(
      param: ["Group", "figure"],
      source: "
        <> Group
          width=12em
          <> img
            src=test.jpg
      ",
      expected: "
        <> Group
          <> img
            style=width:12em
            src=test.jpg
      ",
    ),
    infra.AssertiveTestData(
      param: ["Group", "figure"],
      source: "
        <> figure
          style=width:200px;height:150px
          <> img
            src=test.jpg
      ",
      expected: "
        <> figure
          <> img
            style=width:200px;height:150px
            src=test.jpg
      ",
    ),
    infra.AssertiveTestData(
      param: ["Group", "figure"],
      source: "
        <> Group
          width=300px
          <> div
            <> img
              src=nested.jpg
      ",
      expected: "
        <> Group
          <> div
            <> img
              style=width:300px
              src=nested.jpg
      ",
    ),
    infra.AssertiveTestData(
      param: ["Group", "figure"],
      source: "
        <> figure
          style=color:red;width:100px
          <> img
            src=test.jpg
      ",
      expected: "
        <> figure
          style=color:red
          <> img
            style=width:100px
            src=test.jpg
      ",
    ),
    infra.AssertiveTestData(
      param: ["Group", "figure"],
      source: "
        <> figure
          style=color:red
          <> img
            width=100px
            src=test.jpg
      ",
      expected: "
        <> figure
          style=color:red
          <> img
            style=width:100px
            src=test.jpg
      ",
    ),
    infra.AssertiveTestData(
      param: ["Group", "figure"],
      source: "
          <> img
            height=100px
            src=test.jpg
      ",
      expected: "
          <> img
            style=height:100px
            src=test.jpg
      ",
    ),
    infra.AssertiveTestData(
      param: ["Group", "figure"],
      source: "
        <> div
          width=ignored
          <> img
            src=test.jpg
      ",
      expected: "
        <> div
          width=ignored
          <> img
            src=test.jpg
      ",
    ),
  ]
}

pub fn assertive_tests() {
  infra.assertive_test_collection_from_data(name, assertive_tests_data(), constructor)
}
