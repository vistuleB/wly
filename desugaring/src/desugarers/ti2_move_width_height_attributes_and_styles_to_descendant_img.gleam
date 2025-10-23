import gleam/list
import gleam/option.{type Option, Some, None}
import gleam/string
import infrastructure.{type Desugarer, Desugarer, type DesugaringError, DesugaringError, type DesugarerTransform} as infra
import vxml.{type VXML, T, V}
import nodemaps_2_desugarer_transforms as n2t
import blame as bl
import on

// extract height and width from style and attributes
fn extract_height_width_from_style_and_attrs(
  node: VXML,
) -> Result(#(String, String, List(vxml.Attr)), DesugaringError) {
  let assert V(_, _, attrs, _) = node

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

  let new_attrs = case style_attr {
    None -> attrs
    Some(attr) -> case string.trim(attr.val) == "" {
      True -> attrs  // remove empty style attribute
      False -> [attr, ..attrs]
    }
  }

  Ok(#(width_style, height_style, new_attrs))
}



fn construct_new_state(width_style: String, height_style: String) -> Option(String) {
  case width_style, height_style {
    "", "" -> None
    _, "" -> Some(width_style)
    "", _ -> Some(height_style)
    _, _ -> Some(width_style <> ";" <> height_style)
  }
}

// combine existing state with new styles
fn combine_styles(state: Option(String), new_styles: String) -> String {
  case state, new_styles {
    None, "" -> ""
    None, styles -> styles
    Some(existing), "" -> existing
    Some(existing), styles -> existing <> ";" <> styles
  }
}

fn handle_img_case(
  node: VXML,
  state: State,
) -> Result(#(VXML, State), DesugaringError) {
  let assert V(_, _, attrs, _) = node

  // only extract width/height attributes (not from style)
  use #(width_attr, attrs) <- on.ok(
    infra.attrs_extract_unique_key_or_none(attrs, "width")
  )

  use #(height_attr, attrs) <- on.ok(
    infra.attrs_extract_unique_key_or_none(attrs, "height")
  )

  let width_style = width_attr
    |> option.map(fn(attr) { "width:" <> attr.val })
    |> option.unwrap("")

  let height_style = height_attr
    |> option.map(fn(attr) { "height:" <> attr.val })
    |> option.unwrap("")

  let combined_styles = combine_styles(state, construct_new_state(width_style, height_style) |> option.unwrap(""))

  case combined_styles {
    "" -> Ok(#(V(..node, attrs: attrs), state))
    styles -> {
      let style_attr = vxml.Attr(desugarer_blame(98), "style", styles)
      let new_attrs = [style_attr, ..attrs]
      Ok(#(V(..node, attrs: new_attrs), state))
    }
  }
}

// handle ancestor case (group/figure)
fn handle_ancestor_case(
  node: VXML,
  state: State,
  inner: InnerParam,
) -> Result(#(VXML, State), DesugaringError) {
  let assert V(blame, tag, _, _) = node

  case list.contains(inner, tag) {
    False -> Ok(#(node, state))
    True -> {
      // extract width/height from both attributes and style
      use #(width_style, height_style, new_attrs) <- on.ok(
        extract_height_width_from_style_and_attrs(node)
      )

      let new_state = construct_new_state(width_style, height_style)

      // check for conflicting states
      case new_state, state {
        Some(_), Some(_) -> Error(DesugaringError(blame, "conflicting width/height styles from multiple ancestor elements"))
        Some(_), None -> {
          let new_node = V(..node, attrs: new_attrs)
          Ok(#(new_node, new_state))
        }
        None, _ -> {
          let new_node = V(..node, attrs: new_attrs)
          Ok(#(new_node, state))
        }
      }
    }
  }
}

fn v_before_transforming_children(
  node: VXML,
  state: State,
  inner: InnerParam,
) -> Result(#(VXML, State), DesugaringError) {
  let assert V(_, tag, _, _) = node

  case tag == "img" {
    True -> handle_img_case(node, state)
    False -> handle_ancestor_case(node, state, inner)
  }
}

fn v_after_transforming_children(
  node: VXML,
  original_state: State,
  _latest_state: State,
) -> Result(#(VXML, State), DesugaringError) {
  Ok(#(node, original_state))
}

fn nodemap_factory(inner: InnerParam) -> n2t.OneToOneBeforeAndAfterStatefulNodeMap(State) {
   n2t.OneToOneBeforeAndAfterStatefulNodeMap(
    v_before_transforming_children: fn(node, state){
      v_before_transforming_children(node, state, inner)
    },
    v_after_transforming_children: v_after_transforming_children,
    t_nodemap: fn(node, state) {
      let assert T(_, _) = node
      Ok(#(node, state))
    },
  )
}

fn transform_factory(inner: InnerParam) -> DesugarerTransform {
  nodemap_factory(inner)
  |> n2t.one_to_one_before_and_after_stateful_nodemap_2_desugarer_transform(None)
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(param)
}

pub const name = "ti2_move_width_height_attributes_and_styles_to_descendant_img"
fn desugarer_blame(line_no: Int) { bl.Des([], name, line_no) }

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
        <> img
          width=100px
          height=200px
          src=direct.jpg
      ",
      expected: "
        <> img
          style=width:100px;height:200px
          src=direct.jpg
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
