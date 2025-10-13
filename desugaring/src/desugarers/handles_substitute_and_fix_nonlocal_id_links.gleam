import gleam/dict.{type Dict}
import gleam/list
import gleam/option.{type Option, Some, None}
import gleam/regexp.{type Regexp, type Match, Match}
import gleam/result
import gleam/string.{inspect as ins}
import infrastructure.{type Desugarer, Desugarer, type DesugarerTransform, type DesugaringError, type DesugaringWarning, DesugaringError, DesugaringWarning} as infra
import nodemaps_2_desugarer_transforms as n2t
import vxml.{type Attr, type Line, type VXML, Attr, Line, T, V}
import blame.{type Blame} as bl
import on

fn extract_handle_name(match) -> #(String, Bool) {
  let assert Match(_, [_, option.Some(handle_name)]) = match
  case string.ends_with(handle_name, ":page") {
    True -> {
      #(handle_name |> string.drop_end(5), True)
    }
    False -> #(handle_name, False)
  }
}

fn hyperlink_constructor(
    handle: #(Bool, String, String, String),
    page: Bool,
    blame: Blame,
    state: State,
    inner: InnerParam,
) -> Result(VXML, DesugaringError) {
  use our_path <- on.lazy_none_some(
    state.path,
    fn(){ Error(DesugaringError(blame, "handle occurrence when local path is not defined")) },
  )
  let #(page_by_default, value, id, target_path) = handle
  let #(tag, attrs) = case target_path == our_path {
    True -> #(inner.1, inner.3)
    False -> #(inner.2, inner.4)
  }
  let page = page || page_by_default
  let target_path = case page {
    True -> target_path
    False -> target_path <> "#" <> id
  }
  let attrs = [
    Attr(blame, "href", target_path),
    ..attrs
  ]
  Ok(V(
    blame,
    tag,
    attrs,
    [T(blame, [Line(blame, value)])],
  ))
}

type TripleThreat(a, b, c) {
  Success(a)
  Warning(b)
  Failure(c)
}

fn warning_element(
  handle_name: String,
  blame: Blame,
) -> VXML {
  V(
    desugarer_blame(67),
    "span",
    [Attr(desugarer_blame(69), "style", "color:red;background-color:yellow;")],
    [T(desugarer_blame(70), [Line(desugarer_blame(70), "undefined handle at " <> bl.blame_digest(blame) <> ": " <> handle_name)])],
  )
}

fn hyperlink_maybe(
  handle_and_page: #(String, Bool),
  blame: Blame,
  state: State,
  inner: InnerParam,
) -> TripleThreat(VXML, #(VXML, DesugaringWarning), DesugaringError) {
  let #(handle_name, page) = handle_and_page
  case dict.get(state.handles, handle_name) {
    Ok(quad) -> case hyperlink_constructor(quad, page, blame, state, inner) {
      Ok(vxml) -> Success(vxml)
      Error(e) -> Failure(e)
    }
    _ -> {
      Warning(#(
        warning_element(handle_name, blame),
        DesugaringWarning(blame, "handle '" <> handle_name <> "' is not assigned"),
      ))
    }
  }
}

fn is_failure(threat: TripleThreat(a, b, c)) -> Bool {
  case threat {
    Failure(_) -> True
    _ -> False
  }
}

fn matches_2_hyperlinks(
  matches: List(Match),
  blame: Blame,
  state: State,
  inner: InnerParam,
) -> Result(#(List(VXML), List(DesugaringWarning)), DesugaringError) {
  let threats =
    matches
    |> list.map(extract_handle_name)
    |> list.map(hyperlink_maybe(_, blame, state, inner))

  use _ <- on.ok_error(
    list.find(threats, is_failure),
    fn (f) {
      let assert Failure(desugaring_error) = f
      Error(desugaring_error)
    },
  )

  list.fold(
    threats,
    #([], []),
    fn (acc, t) {
      case t {
        Failure(_) -> panic as "bug"
        Success(link_element) -> #([link_element, ..acc.0], acc.1)
        Warning(#(warning_span, warning)) -> #([warning_span, ..acc.0], [warning, ..acc.1])
      }
    }
  )
  |> fn(pair) { #(pair.0 |> list.reverse, pair.1 |> list.reverse) }
  |> Ok
}

fn augment_to_1_mod_3(
  splits: List(String),
) -> List(String) {
  case list.length(splits) % 3 != 1 {
    True -> {
      let assert True = list.is_empty(splits)
      [""]
    }
    False -> splits
  }
}

fn retain_0_mod_3(
  splits: List(String),
) -> List(String) {
  splits
  |> list.index_fold(
    from: [],
    with: fn(acc, split, index) {
      case index % 3 == 0 {
        True -> [split, ..acc]
        False -> acc
      }
    }
  )
  |> list.reverse
}

fn split_2_t(
  split: String,
  blame: Blame,
) -> VXML {
  T(blame, [Line(blame, split)])
}

fn splits_2_ts(
  splits: List(String),
  blame: Blame,
) -> List(VXML) {
  splits
  |> augment_to_1_mod_3
  |> retain_0_mod_3
  |> list.map(split_2_t(_, blame))
}

fn process_line(
  line: Line,
  state: State,
  inner: InnerParam,
) -> Result(#(List(VXML), List(DesugaringWarning)), DesugaringError) {
  let Line(blame, content) = line
  case regexp.scan(inner.5, content) {
    [_, ..] as matches -> {
      let splits = regexp.split(inner.5, content)
      use #(hyperlinks, warnings) <- on.ok(
        matches_2_hyperlinks(matches, blame, state, inner)
      )
      let text_nodes = splits_2_ts(splits, blame)
      Ok(#(list.interleave([text_nodes, hyperlinks]), warnings))
    }
    [] -> Ok(#([T(line.blame, [line])], []))
  }
}

fn process_lines(
  lines: List(Line),
  state: State,
  inner: InnerParam,
) -> Result(#(List(VXML), List(DesugaringWarning)), DesugaringError) {
  use big_list <- on.ok(
    lines
    |> list.map(process_line(_, state, inner))
    |> result.all
  )

  let #(list_list_vxml, list_list_warnings) = big_list |> list.unzip

  let vxmls =
    list_list_vxml
    |> list.flatten                          // you now have a list of t-nodes and of hyperlinks
    |> infra.plain_concatenation_in_list     // adjacent t-nodes are wrapped into single t-node, with 1 line per old t-node (pre-concatenation)

  let warnings =
    list_list_warnings
    |> list.flatten

  Ok(#(vxmls, warnings))
}

fn grand_wrapper_load(
  state: State,
  attrs: List(Attr)
) -> State {
  let #(handles, ids) = list.partition(attrs, fn(attr) {attr.key == "handle"})

  let handles = list.fold(
    handles,
    dict.new(),
    fn(acc, att) {
      let assert [handle_name, page, value, id, path] = att.value |> string.split("|")
      let page = case page {
        ":page" -> True
        "" -> False
        _ -> panic as "malformed GrandWrapper dictionary"
      }
      dict.insert(acc, handle_name, #(page, value, id, path))
    }
  )

  let ids = list.map(
    ids,
    fn(attr) {
      assert attr.key == "id"
      let assert [id, path] = attr.value |> string.split(" ")
      #(id, path)
    }
  )
  |> infra.aggregate_on_first

  State(..state, handles: handles, ids: ids)
}

fn substitute_handle_in_href(
  attr: Attr,
  state: State,
) -> Result(Attr, DesugaringWarning) {
  assert attr.value |> string.starts_with(">>")
  let handle_name = attr.value |> string.drop_start(2)
  let page = handle_name |> string.ends_with(":page")
  let handle_name = case page {
    True -> handle_name |> string.drop_end(5)
    False -> handle_name
  }
  case dict.get(state.handles, handle_name) {
    Ok(#(page_by_default, _, id, target_path)) -> {
      case page || page_by_default {
        True -> Ok(Attr(..attr, value: target_path))
        False -> case target_path == option.unwrap(state.path, "") {
          True -> Ok(Attr(..attr, value: "#" <> id))
          False -> Ok(Attr(..attr, value: target_path <> "#" <> id))
        }
      }
    }
    _ -> Error(DesugaringWarning(attr.blame, "handle '" <> handle_name <> "' is not assigned"))
  }
}

fn substitute_id_in_href(
  attr: Attr,
  state: State,
) -> Result(#(Attr, Option(DesugaringWarning)), DesugaringError) {
  assert attr.value |> string.starts_with("#")
  let id = attr.value |> string.drop_start(1)
  let #(id, page) = case id |> string.ends_with(":page") {
    True -> #(id |> string.drop_end(5), True)
    False -> #(id, False)
  }
  use path <- on.none_some(
    state.path,
    Error(DesugaringError(attr.blame, "id appearing outside outside of path context")),
  )
  use paths <- on.error_ok(
    dict.get(state.ids, id),
    fn(_) {
      let warning = DesugaringWarning(attr.blame, "path not found for id '" <> id <> "'; maybe it's not defined?")
      Ok(#(attr, Some(warning)))
    }
  )
  case list.contains(paths, path) {
    True -> {
      // the page we're pointing to is
      // the current page, nothing to do
      case page {
        True -> Ok(#(Attr(..attr, value: path), None)) // (this case is a bit weird but whatever the user says...)
        False -> Ok(#(attr, None))
      }

    }
    False -> case paths {
      [] -> panic as "each id should have at least 1 path?"
      [one] -> case page {
        True -> Ok(#(Attr(..attr, value: one), None))
        False -> Ok(#(Attr(..attr, value: one <> attr.value), None))
      }
      _ -> Error(DesugaringError(attr.blame, "unresolved id '" <> id <> "' appearing out-of-own-page but with several target pages to choose from"))
    }
  }
}

fn substitute_in_href(
  attr: Attr,
  state: State,
) -> Result(#(Attr, Option(DesugaringWarning)), DesugaringError) {
  use <- on.false_true(
    attr.key == "href",
    Ok(#(attr, None)),
  )

  let #(attr, warning) = case attr.value |> string.starts_with(">>") {
    False -> #(attr, None)
    True -> case substitute_handle_in_href(attr, state) {
      Ok(attr) -> #(attr, None)
      Error(w) -> #(attr, Some(w))
    }
  }

  use <- on.lazy_false_true(
    attr.value |> string.starts_with("#"),
    fn() { Ok(#(attr, warning)) }
  )

  // note that at this point, 'warning' is necessarily None;
  // we can overwrite it without losing information:

  use #(attr, warning) <- on.ok(substitute_id_in_href(attr, state))
  Ok(#(attr, warning))
}

fn substitute_in_hrefs(
  attrs: List(Attr),
  state: State,
) -> Result(#(List(Attr), List(DesugaringWarning)), DesugaringError) {
  list.try_fold(
    attrs,
    #([], []),
    fn(acc, attr) {
      case substitute_in_href(attr, state) {
        Ok(#(attr, None)) -> Ok(#([attr, ..acc.0], acc.1))
        Ok(#(attr, Some(warning))) -> Ok(#([attr, ..acc.0], [warning, ..acc.1]))
        Error(z) -> Error(z)
      }
    }
  )
}

fn update_state_path(
  state: State,
  vxml: VXML,
  inner: InnerParam,
) -> State {
  let assert V(_, _, _, _) = vxml
  case infra.v_first_attr_with_key(vxml, inner.0) {
    Some(Attr(_, _, value)) -> State(..state, path: Some(value))
    None -> state
  }
}

fn v_before_transform(
  vxml: VXML,
  state: State,
  inner: InnerParam,
) -> Result(#(VXML, State, List(DesugaringWarning)), DesugaringError) {
  let assert V(_, tag, attrs, _) = vxml
  case tag == "GrandWrapper" {
    True -> {
      let state = grand_wrapper_load(state, attrs)
      Ok(#(vxml, state, []))
    }
    False -> {
      let state = update_state_path(state, vxml, inner)
      use #(attrs, warnings) <- on.ok(substitute_in_hrefs(attrs, state))
      Ok(#(V(..vxml, attrs: attrs |> list.reverse), state, warnings))
    }
  }
}

fn v_after_transform(
  vxml: VXML,
  state: State,
) -> Result(#(List(VXML), State, List(DesugaringWarning)), DesugaringError) {
  let assert V(_, tag, _, children)  = vxml
  case tag == "GrandWrapper" {
    True -> {
      let assert [V(_, _, _, _) as root] = children
      Ok(#([root], state, []))
    }
    False -> Ok(#([vxml], state, []))
  }
}

fn t_transform(
  vxml: VXML,
  state: State,
  inner: InnerParam,
) -> Result(#(List(VXML), State, List(DesugaringWarning)), DesugaringError) {
  let assert T(_, lines)  = vxml
  use #(updated_lines, warnings) <- on.ok(process_lines(lines, state, inner))
  Ok(#(updated_lines, state, warnings))
}

fn nodemap_factory(inner: InnerParam) -> n2t.OneToManyBeforeAndAfterStatefulNodeMapWithWarnings(State) {
  n2t.OneToManyBeforeAndAfterStatefulNodeMapWithWarnings(
    v_before_transforming_children: fn(vxml, state) {v_before_transform(vxml, state, inner)},
    v_after_transforming_children: fn(vxml, _, new) {v_after_transform(vxml, new)},
    t_nodemap: fn(vxml, state) { t_transform(vxml, state, inner) },
  )
}

fn transform_factory(inner: InnerParam) -> DesugarerTransform {
  nodemap_factory(inner)
  |> n2t.one_to_many_before_and_after_stateful_nodemap_with_warnings_2_desufarer_transform(State(dict.new(), dict.new(), None))
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  let assert Ok(handles_regexp) = regexp.from_string("(>>)([\\w\\^-]+(?:\\:page)?)")
  #(
    param.0,
    param.1,
    param.2,
    param.3 |> infra.string_pairs_2_attrs(desugarer_blame(445)),
    param.4 |> infra.string_pairs_2_attrs(desugarer_blame(446)),
    handles_regexp, // inner.5
  )
  |> Ok
}

type HandlesDict = Dict(String, #(Bool,     String,   String,   String))
//                      ↖         ↖         ↖         ↖         ↖
//                      handle    :page-by  value     id        path
//                                default
//                                option

type IdsDict = Dict(String, List(String))
//                  ↖       ↖
//                  id      list of pages (local paths)
//                          where id appears

type State {
  State(
    handles: HandlesDict,
    ids: IdsDict,
    path: Option(String),
  )
}

type Param = #(String,            String,                 String,                List(#(String, String)),   List(#(String, String)))
//             ↖                  ↖                       ↖                      ↖                          ↖
//             attr key      tag to use              tag to use             additional key-value       additional key-value
//             to update the      when handle path        when handle path       pairs for former case      pairs for latter case
//             local path         equals local path       !equals local path
//                                at point of insertion   at point of insertion
type InnerParam = #(String, String, String, List(Attr), List(Attr), Regexp)

pub const name = "handles_substitute_and_fix_nonlocal_id_links"
fn desugarer_blame(line_no: Int) { bl.Des([], name, line_no) }

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// Expects a document with root 'GrandWrapper'
/// whose attrs comprise of key-value pairs of
/// the form
///
/// handle=handle_name|value|id|path
///
/// and
///
/// id=id_value|path
///
/// and with a unique child being the root of the
/// original document.
///
/// Replaces >>handle_name occurrences by links,
/// using two different kinds of tags for links
/// that point to elements in the same page versus
/// links that point element in a different page,
/// as provided by the Param argument.
///
/// More specifically, given an occurrence
/// >>handle_name where handle_name points to an
/// element of path 'path' as given by one of the
/// key-value pairs in GrandWrapper, determines if
/// 'path' is in another page of the final set of
/// pages with respect to the current page of the
/// document by trying to look up the latter on the
/// latest (closest) ancestor of the element whose
/// tag is an element of the first list in the
/// desugarer's Param argument, looking at the
/// attr value of the attr whose key is
/// the second argument of Param. The third and
/// fourth arguments of Param specify which tags
/// and classes to use for the in- and out- page
/// links respectively. If the class list is empty
/// no 'class' attr will be added at all to
/// that type of link element.
///
/// Secondly, substitutes each attr of the
/// form
///
/// href=>>handle_name
///
/// with
///
/// ref=<path>#<id>
///
/// where <path> is the associated path and <id>
/// is the associated id to handle_name, as given
/// by the GrandWrapper dictionary; and of the form
///
/// ref=>>handle_name:page
///
/// with
///
/// ref=<path>
///
/// without the '#<id>' portion. (I.e., simply linking
/// to the page containing the element.)
///
/// Thirdly, substitutes attrs of the form
///
/// href=#<id_val>
///
/// with
///
/// href=<path>#<id_val>
///
/// when #id_val is an id whose associated page (if
/// unique) is different from the current page. (I.e.,
/// fixes id-based links to work across pages when
/// possible.)
///
/// Destroys the GrandWrapper root note on exit,
/// returning its unique child.
///
/// Throws a DesugaringError if a given handle or id
/// name is not found in the GrandWrapper data, of
/// if the local 'path' param is missing at any point
/// in the document where a substitution needs to be
/// made.
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
      param:    #(
                  "path",
                  "InChapterLink",
                  "a",
                  [#("class", "handle-in-chapter-link")],
                  [#("class", "handle-out-chapter-link")],
                ),
      source:   "
                <> GrandWrapper
                  handle=fluescence||AA|_23-super-id|./ch1.html
                  <> root
                    <> Chapter
                      path=./ch1.html
                      <>
                        \"some text with >>fluescence in it\"
                      <> Math
                        <>
                          \"$x^2 + b^2$\"
                ",
      expected: "
                <> root
                  <> Chapter
                    path=./ch1.html
                    <>
                      \"some text with \"
                    <> InChapterLink
                      href=./ch1.html#_23-super-id
                      class=handle-in-chapter-link
                      <>
                        \"AA\"
                    <>
                      \" in it\"
                    <> Math
                      <>
                        \"$x^2 + b^2$\"
                ",
    ),
     infra.AssertiveTestData(
      param:    #(
                  "testerpath",
                  "inLink",
                  "outLink",
                  [#("class", "handle-in-link-class")],
                  [#("class", "handle-out-link-class")],
                ),
      source:   "
                <> GrandWrapper
                  handle=fluescence||AA|_23-super-id|./ch1.html
                  handle=out||AA|_24-super-id|./ch1.html
                  <> root
                    <> Page
                      testerpath=./ch1.html
                      <>
                        \"some text with >>fluescence in it\"
                      <> Math
                        <>
                          \"$x^2 + b^2$\"
                    <> Page
                      testerpath=./ch2.html
                      <>
                        \"this is >>out outer link\"
                ",
      expected: "
                <> root
                  <> Page
                    testerpath=./ch1.html
                    <>
                      \"some text with \"
                    <> inLink
                      href=./ch1.html#_23-super-id
                      class=handle-in-link-class
                      <>
                        \"AA\"
                    <>
                      \" in it\"
                    <> Math
                      <>
                        \"$x^2 + b^2$\"
                  <> Page
                    testerpath=./ch2.html
                    <>
                      \"this is \"
                    <> outLink
                      href=./ch1.html#_24-super-id
                      class=handle-out-link-class
                      <>
                        \"AA\"
                    <>
                      \" outer link\"
                ",
    ),
    infra.AssertiveTestData(
      param:    #(
                  "path",
                  "InChapterLink",
                  "a",
                  [#("class", "handle-in-chapter-link")],
                  [#("class", "handle-out-chapter-link")],
                ),
      source:   "
                <> GrandWrapper
                  handle=my-cardinal||Cardinal Number|_25-dash-id|./ch1.html
                  handle=test^handle||Caret Test|_26-caret-id|./ch1.html
                  <> root
                    <> Chapter
                      path=./ch1.html
                      <>
                        \"Reference to >>my-cardinal and >>test^handle here\"
                      <> Math
                        <>
                          \"$x^2 + b^2$\"
                ",
      expected: "
                <> root
                  <> Chapter
                    path=./ch1.html
                    <>
                      \"Reference to \"
                    <> InChapterLink
                      href=./ch1.html#_25-dash-id
                      class=handle-in-chapter-link
                      <>
                        \"Cardinal Number\"
                    <>
                      \" and \"
                    <> InChapterLink
                      href=./ch1.html#_26-caret-id
                      class=handle-in-chapter-link
                      <>
                        \"Caret Test\"
                    <>
                      \" here\"
                    <> Math
                      <>
                        \"$x^2 + b^2$\"
                ",
    )
  ]
}

pub fn assertive_tests() {
  infra.assertive_test_collection_from_data(name, assertive_tests_data(), constructor)
}
