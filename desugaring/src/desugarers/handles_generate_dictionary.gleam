import gleam/dict.{type Dict}
import gleam/list
import gleam/option.{type Option, Some, None}
import gleam/string
import infrastructure.{type Desugarer, Desugarer, type DesugarerTransform, type DesugaringError, DesugaringError} as infra
import nodemaps_2_desugarer_transforms as n2t
import vxml.{type Attribute, type VXML, Attribute, V}
import blame.{type Blame} as bl
import on

type HandlesDict =
  Dict(String, #(String,       String,     String))
//     ↖         ↖             ↖           ↖
//     handle    string value  handle id   page path
//     name      of handle     on page     for handle

type State {
  State(
    handles: HandlesDict,
    path: Option(String),
  )
}

fn convert_handles_to_attributes(
  handles: HandlesDict,
) -> List(Attribute) {
  list.map2(
    dict.keys(handles),
    dict.values(handles),
    fn (key, values) {
      let #(value, id, filename) = values
      Attribute(
        blame: desugarer_blame(33),
        key: "handle",
        value: key <> "|" <> value <> "|" <> id <> "|" <> filename,
      )
    }
  )
}

fn check_handle_already_defined(
  new_handle_name: String,
  handles: HandlesDict,
  blame: Blame,
) -> Result(Nil, DesugaringError) {
  case dict.get(handles, new_handle_name) {
    Ok(_) ->
      Error(DesugaringError(
        blame: blame,
        message: "Handle " <> new_handle_name <> " has already been used",
      ))
    Error(_) -> Ok(Nil)
  }
}

type HandleAttributeInfo {
  HandleAttributeInfo(
    handle_name: String,
    id: String,
    value: String,
    blame: Blame,
  )
}

fn extract_handles_attribute_infos(
  attributes: List(Attribute),
) -> #(List(Attribute), List(HandleAttributeInfo)) {
  let #(handle_attributes, other_attributes) =
    attributes
    |> list.partition(fn(att){att.key == "handle"})

  let infos =
    handle_attributes
    |> list.map(fn(att) {
      let assert [handle_name, value, id] = string.split(att.value, "|")
      HandleAttributeInfo(
        handle_name: handle_name,
        id: id,
        value: value,
        blame: att.blame,
      )
    })

  #(other_attributes, infos)
}

fn update_handles(
  state: State,
  handle_infos: List(HandleAttributeInfo),
  inner: InnerParam,
) -> Result(State, DesugaringError) {
  use first, _ <- on.empty_nonempty(
    handle_infos,
    Ok(state),
  )

  use path <- on.lazy_none_some(
    state.path,
    fn(){ Error(DesugaringError(first.blame, "no '" <> inner <> "' attribute found leading up to to handle '" <> first.handle_name <> "'")) },
  )

  use handles <- on.ok(
    handle_infos
    |> list.try_fold(
      state.handles,
      fn(acc, info) {
        use _ <- on.ok(
          check_handle_already_defined(info.handle_name, acc, info.blame)
        )
        Ok(dict.insert(acc, info.handle_name, #(info.value, info.id, path)))
      }
    )
  )

  Ok(State(..state, handles: handles))
}

fn update_path(
  state: State,
  node: VXML,
  inner: InnerParam,
) -> State {
  let assert V(_, _, _, _) = node
  case infra.v_first_attribute_with_key(node, inner) {
    Some(Attribute(_, _, value)) -> State(..state, path: Some(value))
    None -> state
  }
}

fn t_transform(
  vxml: VXML,
  state: State,
) -> Result(#(VXML, State), DesugaringError) {
  Ok(#(vxml, state))
}

fn v_before_transforming_children(
  vxml: VXML,
  state: State,
  inner: InnerParam,
) -> Result(#(VXML, State), DesugaringError) {
  let assert V(b, t, attributes, c) = vxml
  let #(attributes, handle_infos) = extract_handles_attribute_infos(attributes)
  let state = update_path(state, vxml, inner)
  use state <- on.ok(update_handles(state, handle_infos, inner))
  Ok(#(V(b, t, attributes, c), state))
}

fn v_after_transforming_children(
  vxml: VXML,
  ancestors: List(VXML),
  original_state: State,
  latest_state: State,
) -> Result(#(VXML, State), DesugaringError) {
  let state = State(latest_state.handles, original_state.path)
  case list.is_empty(ancestors) {
    False -> Ok(#(vxml, state))
    True -> {
      let grand_wrapper = V(
        desugarer_blame(160),
        "GrandWrapper",
        convert_handles_to_attributes(state.handles),
        [vxml],
      )
      Ok(#(grand_wrapper, state))
    }
  }
}

fn nodemap_factory(inner: InnerParam) -> n2t.FancyOneToOneBeforeAndAfterStatefulNodeMap(State) {
   n2t.FancyOneToOneBeforeAndAfterStatefulNodeMap(
    v_before_transforming_children: fn(vxml, _, _, _, _, state) {
      v_before_transforming_children(vxml, state, inner)
    },
    v_after_transforming_children: fn(vxml, ancestors, _, _, _, original_state, latest_state) {
      v_after_transforming_children(vxml, ancestors, original_state, latest_state)
    },
    t_nodemap: fn(vxml, _, _, _, _, state) {
      t_transform(vxml, state)
    },
  )
}

fn transform_factory(inner: InnerParam) -> infra.DesugarerTransform {
  n2t.fancy_one_to_one_before_and_after_stateful_nodemap_2_desugarer_transform(
    nodemap_factory(inner),
    State(dict.new(), None)
  )
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(param)
}

type Param = String
//           ↖
//           key of attribute
//           holding the
type InnerParam = Param

pub const name = "handles_generate_dictionary"
fn desugarer_blame(line_no: Int) {bl.Des([], name, line_no)}

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// Looks for `handle` attributes in the V nodes
/// that are expected to be in form
///
/// `handle=handle_name | id | value`
///
/// (Panics if not in this form.)
///
/// Transform the values into a dict where the key
/// is the handle name and the values are tuples
/// #(String, String, String) comprising the handle,
/// id, and value.
///
/// Adds new field of data (path) which represents
/// the filename and is expected to be available
/// In attribute value of node with Param.0 tag
/// Param.1 attribute_key.
///
/// Wraps the document root by a V node with tag
/// GrandWrapper and transform back the dict as the
/// grandwrapper's attributes.
///
/// Returns a pair of newly created node and state
/// of handles used to check for name uniqueness.
///
/// Throws error if
/// 1. there are multiple handles with same
///    handle_name
/// 2. no node found with Param.0 tag Param.1
///    attribute_key
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
      param: "local_path",
      source:   "
                <> root
                  <> ChapterChapter
                    local_path=./ch1.html
                    <>
                      \"some text\"
                    <> Math
                      handle=super-name|AA|_23-super-id
                      <>
                        \"$x^2 + b^2$\"
                ",
      expected: "
                <> GrandWrapper
                  handle=super-name|AA|_23-super-id|./ch1.html
                  <> root
                    <> ChapterChapter
                      local_path=./ch1.html
                      <>
                        \"some text\"
                      <> Math
                        <>
                          \"$x^2 + b^2$\"
                "
    ),
  ]
}

pub fn assertive_tests() {
  infra.assertive_test_collection_from_data(name, assertive_tests_data(), constructor)
}
