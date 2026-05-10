import blame.{type Blame} as bl
import gleam/dict.{type Dict}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/regexp.{type Match, type Regexp, Match}
import gleam/result
import gleam/string.{inspect as ins}
import infrastructure.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
  type DesugaringWarning, Desugarer, DesugaringError, DesugaringWarning,
} as infra
import nodemaps_2_desugarer_transforms as n2t
import on
import vxml.{type Attr, type Line, type VXML, Attr, Line, T, V}

fn extract_handle_and_page_and_decoy(match: Match) -> #(String, Bool, Option(String)) {
  let assert Match(_, [_, option.Some(handle_name)]) = match
  let #(handle_name, page) = case string.split_once(handle_name,  "#page") {
    Ok(#(before, after)) -> #(before <> after, True)
    _ -> #(handle_name, False)
  }
  let #(handle_name, decoy) = case string.split_once(handle_name, "#decoy:") {
    Ok(#(before, after)) -> #(before, option.Some(after))
    _ -> #(handle_name, None)
  }
  #(handle_name, page, decoy)
}


fn hyperlink_constructor(
  handle: #(Bool, String, String, String),
  page: Bool,
  blame: Blame,
  state: State,
  inner: InnerParam,
) -> Result(VXML, DesugaringError) {
  let #(page_by_default, value, id, target_path) = handle

  // dispatch the case where we don't even want a link:
  use _ <- on.stay(case state.inside_a_link_tag {
    False -> on.Stay(Nil)
    True -> on.Return(Ok(T(blame, [Line(blame, value)])))
  })

  // back to constructing a link:
  use our_path <- on.none_some(state.path, fn() {
    Error(DesugaringError(
      blame,
      "handle occurrence when local path is not defined",
    ))
  })
  let #(tag, attrs) = case target_path == our_path {
    True -> #(inner.1, inner.3)
    False -> #(inner.2, inner.4)
  }
  let page = page || page_by_default
  let target_path = case page {
    True -> target_path
    False -> target_path <> "#" <> id
  }
  let attrs = [Attr(blame, "href", target_path), ..attrs]
  Ok(V(blame, tag, attrs, [T(blame, [Line(blame, value)])]))
}

fn warning_element(handle_name: String, blame: Blame) -> VXML {
  V(
    desugarer_blame(66),
    "InTextWarning",
    [],
    [
      T(desugarer_blame(70), [
        Line(
          desugarer_blame(72),
          "undefined handle at "
            <> bl.blame_digest(blame)
            <> ": "
            <> handle_name,
        ),
      ]),
    ],
  )
}

fn hyperlink_maybe(
  handle_and_page_and_decoy: #(String, Bool, Option(String)),
  blame: Blame,
  state: State,
  inner: InnerParam,
) -> Result(#(VXML, List(DesugaringWarning)), DesugaringError) {
  let #(handle_name, page, decoy) = handle_and_page_and_decoy
  use _ <- on.ok_error(
    dict.get(state.handles, handle_name),
    fn(quad) {
      hyperlink_constructor(quad, page, blame, state, inner)
      |> result.try(fn(vxml) { Ok(#(vxml, [])) } )
    }
  )

  use warning_span_or_decoy_link <- on.ok(case decoy {
    None -> Ok(warning_element(handle_name, blame))
    Some(decoy) -> {
      let quad = #(False, decoy, "decoy-id", "decoy-target-path")
      hyperlink_constructor(quad, page, blame, state, inner)
    }
  })

  let actual_warning = DesugaringWarning(
    desugarer_blame(107),
    "handle '" <> handle_name <> "' is not assigned",
  )

  Ok(#(warning_span_or_decoy_link, [actual_warning]))
}

fn matches_2_hyperlinks(
  matches: List(Match),
  blame: Blame,
  state: State,
  inner: InnerParam,
) -> Result(#(List(VXML), List(DesugaringWarning)), DesugaringError) {
  let handles_and_pages_and_decoys = matches |> list.map(extract_handle_and_page_and_decoy)
  use #(vxmls, warnings) <- on.ok(list.try_fold(
    handles_and_pages_and_decoys,
    #([], []),
    fn(acc, handle_and_page_and_decoy) {
      use #(vxml, warnings) <- on.ok(hyperlink_maybe(handle_and_page_and_decoy, blame, state, inner))
      Ok(#([vxml, ..acc.0], infra.pour(warnings, acc.1)))
    }
  ))
  Ok(#(vxmls |> list.reverse, warnings |> list.reverse))
}

fn augment_to_1_mod_3(splits: List(String)) -> List(String) {
  case list.length(splits) % 3 != 1 {
    True -> {
      let assert True = list.is_empty(splits) as { ins(splits) }
      [""]
    }
    False -> splits
  }
}

fn retain_0_mod_3(splits: List(String)) -> List(String) {
  splits
  |> list.index_fold(from: [], with: fn(acc, split, index) {
    case index % 3 == 0 {
      True -> [split, ..acc]
      False -> acc
    }
  })
  |> list.reverse
}

fn split_2_t(split: String, blame: Blame) -> VXML {
  T(blame, [Line(blame, split)])
}

fn splits_2_ts(splits: List(String), blame: Blame) -> List(VXML) {
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
      use #(hyperlinks, warnings) <- on.ok(matches_2_hyperlinks(
        matches,
        blame,
        state,
        inner,
      ))
      let text_nodes = splits_2_ts(splits, blame)
      let vxmls = 
        list.interleave([text_nodes, hyperlinks])
        |> infra.last_to_first_concatenation
      Ok(#(vxmls, warnings))
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
    |> result.all,
  )

  let #(list_list_vxml, list_list_warnings) = big_list |> list.unzip

  let vxmls =
    list_list_vxml
    |> list.flatten
    |> infra.plain_concatenation_in_list

  let warnings =
    list_list_warnings
    |> list.flatten

  Ok(#(vxmls, warnings))
}

fn grand_wrapper_load(state: State, attrs: List(Attr)) -> State {
  let #(handles, ids) = infra.attrs_extract_key_occurrences(attrs, "handle")

  let handles =
    list.fold(handles, dict.new(), fn(acc, attr) {
      let assert [handle_name, page, value, id, path] =
        attr.val |> string.split("|")
      let page = case page {
        "#page" -> True
        "" -> False
        _ -> panic as "malformed GrandWrapper dictionary"
      }
      dict.insert(acc, handle_name, #(page, value, id, path))
    })

  let ids =
    list.map(ids, fn(attr) {
      assert attr.key == "id"
      let assert [id, path] = attr.val |> string.split(" ")
      #(id, path)
    })
    |> infra.aggregate_on_first

  State(..state, handles: handles, ids: ids)
}

type HrefType {
  InPage
  OutOfPage
  UndefinedOrOutOfDocument
  NotAnHref
}

fn substitute_handle_in_href(
  attr: Attr,
  state: State,
) -> #(Attr, HrefType, List(DesugaringWarning)) {
  assert attr.val |> string.starts_with(">>")
  let handle_name = attr.val |> string.drop_start(2)
  let #(page, handle_name) = case string.ends_with(handle_name, "#page") {
    True -> #(True, handle_name |> string.drop_end(5))
    False -> #(False, handle_name)
  }
  case dict.get(state.handles, handle_name) {
    Ok(#(page_by_default, _, id, target_path)) -> {
      let href_type = case target_path == option.unwrap(state.path, "") {
        True -> InPage
        False -> OutOfPage
      }
      let attr = case page || page_by_default, href_type {
        True, _ -> Attr(..attr, val: target_path)
        False, InPage -> Attr(..attr, val: "#" <> id)
        False, OutOfPage -> Attr(..attr, val: target_path <> "#" <> id)
        False, _ -> panic
      }
      #(attr, href_type, [])
    }
    _ -> {
      let warning = DesugaringWarning(
        attr.blame,
        "handle '" <> handle_name <> "' is not assigned",
      )
      #(attr, UndefinedOrOutOfDocument, [warning])
    }
  }
}

fn substitute_id_in_href(
  attr: Attr,
  state: State,
) -> Result(#(Attr, HrefType, List(DesugaringWarning)), DesugaringError) {
  assert attr.val |> string.starts_with("#")
  let id = attr.val |> string.drop_start(1)
  let #(id, page) = case id |> string.ends_with("#page") {
    True -> #(id |> string.drop_end(5), True)
    False -> #(id, False)
  }
  use path <- on.none_some(state.path, fn() {
    Error(DesugaringError(
      attr.blame,
      "id appearing outside outside of path context",
    ))
  })
  use paths <- on.error_ok(dict.get(state.ids, id), fn(_) {
    let warning =
      DesugaringWarning(
        attr.blame,
        "path not found for id '" <> id <> "'; maybe it's not defined?",
      )
    Ok(#(attr, UndefinedOrOutOfDocument, [warning]))
  })
  case list.contains(paths, path) {
    True -> {
      // the page we're pointing to is
      // the current page, nothing to do
      case page {
        True -> Ok(#(Attr(..attr, val: path), InPage, []))
        False -> Ok(#(attr, InPage, []))
      }
    }
    False ->
      case paths {
        [] -> panic as "each id should have at least 1 path?"
        [one] ->
          case page {
            True -> Ok(#(Attr(..attr, val: one), OutOfPage, []))
            False -> Ok(#(Attr(..attr, val: one <> attr.val), OutOfPage, []))
          }
        _ ->
          Error(DesugaringError(
            attr.blame,
            "unresolved id '"
              <> id
              <> "' appearing out-of-own-page but with several target pages to choose from",
          ))
      }
  }
}

fn substitute_in_href(
  attr: Attr,
  state: State,
) -> Result(#(Attr, HrefType, List(DesugaringWarning)), DesugaringError) {
  use <- on.false_true(
    attr.key == "href",
    fn() { Ok(#(attr, NotAnHref, [])) }
  )

  case attr.val {
    ">>" <> _ -> substitute_handle_in_href(attr, state) |> Ok
    "#" <> _ -> substitute_id_in_href(attr, state)
    _ -> Ok(#(attr, UndefinedOrOutOfDocument, []))
  }
}

fn substitute_hrefs_in_a(
  vxml: VXML,
  state: State,
  inner: InnerParam,
) -> Result(#(VXML, State, List(DesugaringWarning)), DesugaringError) {
  let assert V(_, "a", attrs, _) = vxml
  use #(attrs, acc) <- on.ok(infra.try_map_fold(
    attrs,
    #(None, []),
    fn(acc, attr) {
      use #(attr, href_type, warnings) <- on.ok(substitute_in_href(attr, state))
      use acc0 <- on.ok(
        case acc.0, href_type {
          _, NotAnHref -> Ok(acc.0)
          None, _ -> Ok(Some(href_type))
          _, _ -> Error(DesugaringError(desugarer_blame(364), "duplicate 'href' attribute"))
        }
      )
      Ok(#(attr, #(acc0, list.append(warnings, acc.1))))
    }
  ))
  let tag = case acc.0 {
    Some(InPage) -> inner.1
    Some(OutOfPage) -> inner.2
    _ -> vxml.tag
  }
  Ok(#(V(..vxml, tag: tag, attrs: attrs), state, acc.1))
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
  let state = case tag {
    "GrandWrapper" -> grand_wrapper_load(state, attrs)
    _ -> update_state_path(state, vxml, inner)
  }
  let state = case state.inside_a_link_tag || !list.contains(inner.6, tag) {
    True -> state
    False -> State(..state, inside_a_link_tag: True)
  }
  case tag {
    "a" -> substitute_hrefs_in_a(vxml, state, inner)
    _ -> Ok(#(vxml, state, []))
  }
}

fn v_after_transform(
  vxml: VXML,
  original_state: State,
  latest_state: State,
) -> Result(#(List(VXML), State, List(DesugaringWarning)), DesugaringError) {
  let assert V(_, tag, _, children) = vxml
  // this is incorrect we should just use original_state but
  // min changes for now:
  let exit_state = State(..latest_state, inside_a_link_tag: original_state.inside_a_link_tag)
  case tag == "GrandWrapper" {
    True -> {
      let assert [V(_, _, _, _) as root] = children
      Ok(#([root], exit_state, []))
    }
    False -> Ok(#([vxml], exit_state, []))
  }
}

fn t_transform(
  vxml: VXML,
  state: State,
  inner: InnerParam,
) -> Result(#(List(VXML), State, List(DesugaringWarning)), DesugaringError) {
  let assert T(_, lines) = vxml
  use #(updated_lines, warnings) <- on.ok(process_lines(lines, state, inner))
  Ok(#(updated_lines, state, warnings))
}

fn nodemap_factory(
  inner: InnerParam,
) -> n2t.OneToManyBeforeAndAfterStatefulNodemapWithWarnings(State) {
  n2t.OneToManyBeforeAndAfterStatefulNodemapWithWarnings(
    v_before_transforming_children: fn(vxml, state) {
      v_before_transform(vxml, state, inner)
    },
    v_after_transforming_children: fn(vxml, original_state, latest_state) {
      v_after_transform(vxml, original_state, latest_state)
    },
    t_nodemap: fn(vxml, state) { t_transform(vxml, state, inner) },
  )
}

fn transform_factory(inner: InnerParam) -> DesugarerTransform {
  nodemap_factory(inner)
  |> n2t.one_to_many_before_and_after_stateful_nodemap_with_warnings_2_desufarer_transform(
    State(dict.new(), dict.new(), None, False),
  )
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  let assert Ok(handles_regexp) =
    regexp.from_string("(>>)([\\w\\^+%-]+(?:#page)?(?:#decoy:[0-9]+)?)")

  #(
    param.0,
    param.1,
    param.2,
    param.3 |> infra.string_pairs_2_attrs(desugarer_blame(467)),
    param.4 |> infra.string_pairs_2_attrs(desugarer_blame(468)),
    handles_regexp,
    param.5,
  )
  |> Ok
}

type HandlesDict = Dict(String, #(Bool,     String,   String,   String))
//                      ↖         ↖         ↖         ↖         ↖
//                      handle    #page-by  value     id        path
//                               #default
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
    inside_a_link_tag: Bool,
  )
}

type Param = #(String,            String,                 String,                List(#(String, String)),   List(#(String, String)),   List(String))
//             ↖                  ↖                       ↖                      ↖                          ↖                          ↖
//             attr key           tag to use              tag to use             additional attribute       additional attribute       tags that count as
//             to update the      when handle path        when handle path       key-value pairs for        key-value pairs for        "already being inside a link"
//             local path         equals local path       !equals local path     former case                latter case 
//                                at point of insertion   at point of insertion
type InnerParam = #(String, String, String, List(Attr), List(Attr), Regexp, List(String))

pub const name = "handles_substitute_and_fix_nonlocal_id_links"

fn desugarer_blame(line_no: Int) {
  bl.Des([], name, line_no)
}

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
/// ref=>>handle_name#page
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
      param: #(
        "path",
        "InChapterLink",
        "a",
        [#("class", "handle-in-chapter-link")],
        [#("class", "handle-out-chapter-link")],
        ["a"],
      ),
      source: "
                <> GrandWrapper
                  handle=fluescence||AA|_23-super-id|./ch1.html
                  <> root
                    <> Chapter
                      path=./ch1.html
                      <>
                        'some text with >>fluescence in it'
                      <> Math
                        <>
                          '$x^2 + b^2$'
                ",
      expected: "
                <> root
                  <> Chapter
                    path=./ch1.html
                    <>
                      'some text with '
                    <> InChapterLink
                      href=./ch1.html#_23-super-id
                      class=handle-in-chapter-link
                      <>
                        'AA'
                    <>
                      ' in it'
                    <> Math
                      <>
                        '$x^2 + b^2$'
                ",
    ),
    infra.AssertiveTestData(
      param: #(
        "testerpath",
        "inLink",
        "outLink",
        [#("class", "handle-in-link-class")],
        [#("class", "handle-out-link-class")],
        ["a"],
      ),
      source: "
                <> GrandWrapper
                  handle=fluescence||AA|_23-super-id|./ch1.html
                  handle=out||AA|_24-super-id|./ch1.html
                  <> root
                    <> Page
                      testerpath=./ch1.html
                      <>
                        'some text with >>fluescence in it'
                      <> Math
                        <>
                          '$x^2 + b^2$'
                    <> Page
                      testerpath=./ch2.html
                      <>
                        'this is >>out outer link'
                ",
      expected: "
                <> root
                  <> Page
                    testerpath=./ch1.html
                    <>
                      'some text with '
                    <> inLink
                      href=./ch1.html#_23-super-id
                      class=handle-in-link-class
                      <>
                        'AA'
                    <>
                      ' in it'
                    <> Math
                      <>
                        '$x^2 + b^2$'
                  <> Page
                    testerpath=./ch2.html
                    <>
                      'this is '
                    <> outLink
                      href=./ch1.html#_24-super-id
                      class=handle-out-link-class
                      <>
                        'AA'
                    <>
                      ' outer link'
                ",
    ),
    infra.AssertiveTestData(
      param: #(
        "path",
        "InChapterLink",
        "a",
        [#("class", "handle-in-chapter-link")],
        [#("class", "handle-out-chapter-link")],
        ["a"],
      ),
      source: "
                <> GrandWrapper
                  handle=my-cardinal||Cardinal Number|_25-dash-id|./ch1.html
                  handle=test^handle||Caret Test|_26-caret-id|./ch1.html
                  <> root
                    <> Chapter
                      path=./ch1.html
                      <>
                        'Reference to >>my-cardinal and >>test^handle here'
                      <> Math
                        <>
                          '$x^2 + b^2$'
                ",
      expected: "
                <> root
                  <> Chapter
                    path=./ch1.html
                    <>
                      'Reference to '
                    <> InChapterLink
                      href=./ch1.html#_25-dash-id
                      class=handle-in-chapter-link
                      <>
                        'Cardinal Number'
                    <>
                      ' and '
                    <> InChapterLink
                      href=./ch1.html#_26-caret-id
                      class=handle-in-chapter-link
                      <>
                        'Caret Test'
                    <>
                      ' here'
                    <> Math
                      <>
                        '$x^2 + b^2$'
                ",
    ),
    infra.AssertiveTestData(
      param: #(
        "path",
        "InChapterLink",
        "a",
        [#("class", "handle-in-chapter-link")],
        [#("class", "handle-out-chapter-link")],
        ["a"],
      ),
      source: "
                <> GrandWrapper
                  handle=fluescence|#page|AA|_23-super-id|./ch1.html
                  handle=other||BB|_24-other-id|./ch1.html
                  <> root
                    <> Chapter
                      path=./ch1.html
                      <>
                        'link to >>fluescence and link to >>other#page.'
                ",
      expected: "
                <> root
                  <> Chapter
                    path=./ch1.html
                    <>
                      'link to '
                    <> InChapterLink
                      href=./ch1.html
                      class=handle-in-chapter-link
                      <>
                        'AA'
                    <>
                      ' and link to '
                    <> InChapterLink
                      href=./ch1.html
                      class=handle-in-chapter-link
                      <>
                        'BB'
                    <>
                      '.'
                ",
    ),
    infra.AssertiveTestData(
      param: #(
        "path",
        "InChapterLink",
        "a",
        [#("class", "handle-in-chapter-link")],
        [#("class", "handle-out-chapter-link")],
        ["a"],
      ),
      source: "
                <> GrandWrapper
                  handle=fluescence||AA|_23-super-id|./ch1.html
                  <> root
                    <> Chapter
                      path=./ch2.html
                      <>
                        'link to >>fluescence#page.'
                ",
      expected: "
                <> root
                  <> Chapter
                    path=./ch2.html
                    <>
                      'link to '
                    <> a
                      href=./ch1.html
                      class=handle-out-chapter-link
                      <>
                        'AA'
                    <>
                      '.'
                ",
    ),
    infra.AssertiveTestData(
      param: #(
        "path",
        "InChapterLink",
        "OutChapterLink",
        [#("class", "handle-in-chapter-link")],
        [#("class", "handle-out-chapter-link")],
        ["a"],
      ),
      source: "
        <> GrandWrapper
          handle=slopes||26|section-1|/article/chapter1
          <> Book
            <> Chapter
              path=/article/chapter2
              <> Section
                <>
                  '*Terminology: “dimension” vs. “dimensional”.*'
                  'As explained in the '
                <> a
                  href=>>slopes
                  <>
                    'Epilogue to Chapter >>slopes#decoy:2'
      ",
      expected: "
        <> Book
          <> Chapter
            path=/article/chapter2
            <> Section
              <>
                '*Terminology: “dimension” vs. “dimensional”.*'
                'As explained in the '
              <> OutChapterLink
                href=/article/chapter1#section-1
                <>
                  'Epilogue to Chapter 26'
      ",
    ),
    infra.AssertiveTestData(
      param: #(
        "path",
        "InChapterLink",
        "OutChapterLink",
        [#("class", "handle-in-chapter-link")],
        [#("class", "handle-out-chapter-link")],
        ["a"],
      ),
      source: "
        <> GrandWrapper
          handle=goober||26|section-1|/article/chapter1
          <> Book
            <> Chapter
              path=/article/chapter2
              <> Section
                <>
                  '*Terminology: “dimension” vs. “dimensional”.*'
                  'As explained in the '
                <> a
                  href=>>slopes
                  <>
                    'Epilogue to Chapter >>slopes#decoy:2'
      ",
      expected: "
        <> Book
          <> Chapter
            path=/article/chapter2
            <> Section
              <>
                '*Terminology: “dimension” vs. “dimensional”.*'
                'As explained in the '
              <> a
                href=>>slopes
                <>
                  'Epilogue to Chapter 2'
      ",
    )
  ]
}

pub fn assertive_tests() {
  infra.assertive_test_collection_from_data(
    name,
    assertive_tests_data(),
    constructor,
  )
}
