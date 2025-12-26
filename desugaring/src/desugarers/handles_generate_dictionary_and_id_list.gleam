import gleam/dict.{type Dict}
import gleam/list
import gleam/option.{type Option, Some, None}
import gleam/string
import infrastructure.{type Desugarer, Desugarer, type DesugarerTransform, type DesugaringError, DesugaringError} as infra
import nodemaps_2_desugarer_transforms as n2t
import vxml.{type Attr, type VXML, Attr, V}
import blame.{type Blame} as bl
import splitter as sp
import on

fn grand_wrapper_attrs(
  state: State,
) -> List(Attr) {
  [
    state.handles
    |> dict.map_values(
      fn (key, value) {
        let #(page, value, id, path, _) = value
        let page = case page {
          True -> ":page"
          False -> ""
        }
        Attr(desugarer_blame(24), "handle", key <> "|" <> page <> "|" <> value <> "|" <> id <> "|" <> path)
      }
    )
    |> dict.values,
    state.ids
    |> list.map(
      fn(x) {
        Attr(desugarer_blame(31), "id", x.0 <> " " <> x.1)
      }
    )
  ]
  |> list.flatten
}

fn try_read_handle(
  attr: Attr
) -> Result(#(String, Bool, String, String), DesugaringError) {
  assert attr.key == "handle"
  case string.split(attr.val, "|") {
    [name, value, id] -> {
      case name |> string.ends_with(":page") {
        False -> Ok(#(name, False, value, id))
        True -> Ok(#(name |> string.drop_end(5), True, value, id))
      }
    }
    _ -> Error(DesugaringError(attr.blame, "handle attr not in form <name>|<value>|<id>; found: “" <> attr.val <> "”"))
  }
}

fn try_insert_handle(
  handles: HandlesDict,
  name: String,
  page: Bool,
  value: String,
  id: String,
  path: String,
  blame: Blame,
) -> Result(HandlesDict, DesugaringError) {
  case dict.get(handles, name) {
    Ok(entry) ->
      Error(DesugaringError(blame, "redefinition of '" <> name <> "' (previously defined at " <> bl.blame_digest(entry.4) <> ")"))
    Error(_) ->
      Ok(dict.insert(handles, name, #(page, value, id, path, blame)))
  }
}

fn try_insert_id(
  ids: Ids,
  attr: Attr,
  path: String,
) -> Result(Ids, DesugaringError) {
  assert attr.key == "id"

  let id = attr.val

  use <- on.true_false(
    id == "",
    fn() { Error(DesugaringError(attr.blame, "empty string id")) }
  )

  use <- on.true_false(
    string.contains(id, " "),
    fn() { Error(DesugaringError(attr.blame, "id attr contains space: '" <> id <> "'")) }
  )

  case list.find(ids, fn(x) { x.0 == id && x.1 == path }) {
    Ok(x) -> 
      Error(DesugaringError(
        attr.blame,
        "redefinition id '" <> id <> "' on page '" <> path <> "' (previously defined at " <> bl.blame_digest(x.2) <> ")"
      ))
    Error(_) -> {

      Ok([#(id, path, attr.blame), ..ids])
    }
  }
}

fn attrs_fold(
  not_handles_acc: List(Attr),
  remaining: List(Attr),
  handles: HandlesDict,
  ids: Ids,
  path: String,
) -> Result(#(HandlesDict, Ids, List(Attr)), DesugaringError) {
  use first, rest <- on.empty_nonempty(
    remaining,
    fn() { Ok(#(handles, ids, not_handles_acc |> list.reverse)) },
  )

  case first.key {
    "handle" -> {
      use #(name, page, value, id) <- on.ok(try_read_handle(first))
      use handles <- on.ok(try_insert_handle(handles, name, page, value, id, path, first.blame))
      attrs_fold(not_handles_acc, rest, handles, ids, path)
    }

    "id" -> {
      use ids <- on.ok(try_insert_id(ids, first, path))
      attrs_fold([first, ..not_handles_acc], rest, handles, ids, path)
    }

    _ -> attrs_fold([first, ..not_handles_acc], rest, handles, ids, path)
  }
}

fn check_no_handles_no_ids(
  attrs: List(Attr)
) -> Result(List(Nil), DesugaringError) {
  list.try_map(
    attrs,
    fn(attr) {
      case attr.key {
        "handle" -> {
          let #(name, _, _) = sp.split(sp.new(["|"]), attr.val)
          Error(DesugaringError(attr.blame, "no page path at handle '" <> name <> "'"))
        }
        "id" -> {
          Error(DesugaringError(attr.blame, "no page path at id '" <> name <> "'"))
        }
        _ -> Ok(Nil)
      }
    }
  )
}

fn update_path(
  state: State,
  node: VXML,
  inner: InnerParam,
) -> State {
  let assert V(_, _, _, _) = node
  case infra.v_first_attr_with_key(node, inner) {
    Some(Attr(_, _, value)) -> State(..state, path: Some(value))
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
  let assert V(_, _, attrs, _) = vxml
  let state = update_path(state, vxml, inner)
  case state.path {
    None -> {
      use _ <- on.ok(check_no_handles_no_ids(attrs))
      Ok(#(vxml, state))
    }
    Some(path) -> {
      use #(handles, ids, attrs) <- on.ok(attrs_fold([], attrs, state.handles, state.ids, path))
      Ok(#(V(..vxml, attrs: attrs), State(..state, handles: handles, ids: ids)))
    }
  }
}

fn v_after_transforming_children(
  vxml: VXML,
  ancestors: List(VXML),
  original_state: State,
  state: State,
) -> Result(#(VXML, State), DesugaringError) {
  let state = State(..state, path: original_state.path)
  case ancestors {
    [] -> {
      let grand_wrapper = V(
        desugarer_blame(198),
        "GrandWrapper",
        grand_wrapper_attrs(state),
        [vxml],
      )
      Ok(#(grand_wrapper, state))
    }
    _ -> Ok(#(vxml, state))
  }
}

fn nodemap_factory(inner: InnerParam) -> n2t.FancyOneToOneBeforeAndAfterStatefulNodemap(State) {
   n2t.FancyOneToOneBeforeAndAfterStatefulNodemap(
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
    State(dict.new(), None, []),
  )
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(param)
}

type HandlesDict = Dict(String, #(Bool,         String,       String,     String,      Blame))
//                      ↖         ↖             ↖             ↖           ↖
//                      handle    ':page' link  string value  handle id   page path
//                      name      by default    of handle     on page     for handle

type Ids = List(#(String, String,     Blame))
//                ↖       ↖
//                id      page path

type State {
  State(
    handles: HandlesDict,
    path: Option(String),
    ids: Ids,
  )
}

type Param = String
//           ↖
//           key of attr
//           holding the local path (could be 'path' or 'page', etc)
type InnerParam = Param

pub const name = "handles_generate_dictionary_and_id_list"
fn desugarer_blame(line_no: Int) { bl.Des([], name, line_no) }

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// Traverses the tree. Expects `handle` attrs
/// to be in the form
/// 
/// `handle=<name>|<value>|<id>`
///
/// without spaces and where `|` is the literal 
/// vertical bar.
/// 
/// Also expects handles attrs to sit on nodes 
/// where one of the ancestors contains an attr
/// of key param. (Typically param = "path".) Throws 
/// error otherwise, or if two handles are found with
/// the same name.
///
/// Wraps the root of the document in a node named
/// 'GrandWrapper' and with attrs of the form
/// 
/// handle=<name>|<:page>|<value>|<id>|<path>
/// 
/// where <path> is the value of the afore-mentioned
/// "path" attr associated to each handle
/// (specifically the value of that attr at the
/// closest ancestor to the node where the handle 
/// sits), and where <:page> is either the string
/// ":page" or the empty string depending on whether
/// original handle <name> ended with the suffix ':page'
/// or not, in which which case that suffix will also
/// be stripped in the <name> field of the GrandWrapper
/// dictionary.
///
/// Removes the original 'handle' attrs from their
/// original positions, with all of the info stored at
/// GrandWrapper.
/// 
/// Also adds an attr of the form
/// 
/// id=<id_val>|<path>
/// 
/// to GrandWrapper for each id=<id_val> attr
/// found in the document, with the same semantics of
/// <path>. By contrast to handles, ids can be
/// multiply-defined as long as they occur with
/// different handles each time.
/// 
/// Throws a DesugaringError if any 'id' or 'handle'
/// occurs in a part of the tree where 'path' is not
/// defined.
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
                      'some text'
                    <> Math
                      handle=super-name|AA|_23-super-id
                      <>
                        '$x^2 + b^2$'
                ",
      expected: "
                <> GrandWrapper
                  handle=super-name||AA|_23-super-id|./ch1.html
                  <> root
                    <> ChapterChapter
                      local_path=./ch1.html
                      <>
                        'some text'
                      <> Math
                        <>
                          '$x^2 + b^2$'
                "
    ),
  ]
}

pub fn assertive_tests() {
  infra.assertive_test_collection_from_data(name, assertive_tests_data(), constructor)
}
