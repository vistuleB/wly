import gleam/int
import gleam/list
import gleam/dict.{type Dict}
import gleam/option.{type Option, None, Some}
import gleam/regexp.{type Regexp}
import gleam/result
import gleam/string.{inspect as ins}
import infrastructure.{type Desugarer, Desugarer, type DesugarerTransform, type DesugaringError, DesugaringError} as infra
import roman
import nodemaps_2_desugarer_transforms as n2t
import vxml.{type Attr, type Line, type VXML, Attr, Line, T, V}
import blame.{type Blame} as bl
import on

type CounterType {
  Arabic
  Roman
  Unary(String)
}

type CounterInfo {
  CounterInfo(
    counter_type: CounterType,
    value: Int,
    step: Int,
  )
}

type CounterDict = Dict(String, CounterInfo)

type HandleAssignment =
  #(String, String)

type StringAndRegexVersion {
  StringAndRegexVersion(string: String, regex_string: String)
}

const loud = StringAndRegexVersion(string: "::", regex_string: "::")
const soft = StringAndRegexVersion(string: "..", regex_string: "\\.\\.")
const increment = StringAndRegexVersion(string: "++", regex_string: "\\+\\+")
const decrement = StringAndRegexVersion(string: "--", regex_string: "--")
const no_change = StringAndRegexVersion(string: "øø", regex_string: "øø")

fn update_info(
  info: CounterInfo,
  mutation: String,
) -> CounterInfo {
  case mutation {
    _ if mutation == increment.string -> CounterInfo(..info, value: info.value + info.step )
    _ if mutation == decrement.string -> CounterInfo(..info, value: info.value - info.step )
    _ if mutation == no_change.string -> info
    _ -> panic as "bad mutation"
  }
}

fn render_counter(
  info: CounterInfo
) -> String {
  case info.counter_type {
    Arabic -> ins(info.value)
    Roman -> roman.int_to_roman(info.value) |> option.unwrap([]) |> roman.roman_to_string()
    Unary(c) -> string.repeat(c, info.value)
  }
}

fn get_all_handles_from_match_content(match_content: String) -> List(String) {
  let assert [_, ..rest] = string.split(match_content, "<<") |> list.reverse()
  list.reverse(rest)
}

type CounterBundle {
  CounterBundle(
    split_char: String,
    insert_or_not: String,
    mutation: String,
    counter_name: String,
  )
}

fn counter_bundles_from_counter_splits(
  splits: List(String),
) -> List(CounterBundle) {
  case splits {
    [] -> []
    [""] -> []
    splits -> {
      let assert [split_char, insert_or_not, mutation, counter_name, ..rest] = splits
      let bundle = CounterBundle(split_char, insert_or_not, mutation, counter_name)
      [bundle, ..counter_bundles_from_counter_splits(rest)]
    }
  }
}

fn get_all_counters_from_match_content(
  match_content: String,
  regexes: #(Regexp, Regexp),
) -> List(CounterBundle) {
  let assert [last, ..] = string.split(match_content, "<<") |> list.reverse()
  let #(re, _) = regexes
  let splits = regexp.split(re, last)
  counter_bundles_from_counter_splits(splits)
}

type TwoValues {
  TwoValues(
    handle_value: String,
    echoed_value: String,
  )
}

type LeftMostSplitChar = String

const empty_values = TwoValues("", "")

fn serialize_counter_bundles(
  bundles: List(CounterBundle),
  counters: CounterDict,
) -> Result(#(LeftMostSplitChar, TwoValues, CounterDict), String) {
  use first, rest <- on.empty_nonempty(bundles, Ok(#("", empty_values, counters)))
  let CounterBundle(our_split_char, insert_or_not, mutation, counter_name) = first
  use info <- on.error_ok(
    dict.get(counters, counter_name),
    fn(_) { Error("counter " <> counter_name <> " is not defined") },
  )
  let info = info |> update_info(mutation)
  let counters = counters |> dict.insert(counter_name, info)
  use #(rest_split_char, rest_two_values, counters) <- on.ok(serialize_counter_bundles(rest, counters))
  let counter_string = render_counter(info)
  let #(bequeathed_split_char, echoed_prefix) = case insert_or_not {
    _ if insert_or_not == loud.string -> #(our_split_char, counter_string <> rest_split_char)
    _ if insert_or_not == soft.string -> #(rest_split_char, "") 
    _ -> panic
  }
  let two_values = TwoValues(
    handle_value: our_split_char <> counter_string <> rest_two_values.handle_value,
    echoed_value: echoed_prefix <> rest_two_values.echoed_value,
  )
  Ok(#(bequeathed_split_char, two_values, counters))
}

fn handle_matches(
  matches: List(regexp.Match),
  splits: List(String),
  counters: CounterDict,
  regexes: #(Regexp, Regexp),
) -> Result(#(String, CounterDict, List(HandleAssignment)), String) {
  case matches {
    [] -> {
      let assert [first_split] = splits
      Ok(#(first_split, counters, []))
    }

    [first, ..rest] -> {
      let regexp.Match(content, sub_matches) = first
      let assert [_, handle_name, ..] = sub_matches
      let counter_expressions =
        get_all_counters_from_match_content(content, regexes)

      use #(_, two_values, updated_counters) <- on.ok(
        serialize_counter_bundles(counter_expressions, counters),
      )

      let handle_names = case handle_name {
        None -> []
        Some(_) -> get_all_handles_from_match_content(content)
      }

      let handle_assignments =
        handle_names |> list.map(fn(x) { #(x, two_values.handle_value) })

      let assert [first_split, _, _, _, _, _, _, _, _, _, _, _, ..rest_splits] =
        splits

      use #(rest_output, updated_counters, rest_handle_assignments) <- on.ok(
        handle_matches(rest, rest_splits, updated_counters, regexes),
      )

      Ok(#(
        first_split <> two_values.echoed_value <> rest_output,
        updated_counters,
        list.flatten([handle_assignments, rest_handle_assignments]),
      ))
    }
  }
}

fn substitute_counters_and_generate_handle_assignments(
  blame: Blame,
  content: String,
  counters: CounterDict,
  regexes: #(Regexp, Regexp),
) -> Result(#(String, CounterDict, List(HandleAssignment)), DesugaringError) {
  // examples

  // 1) one handle | one counter
  // ---------------------------

  // "more handle<<::++MyCounter more" will result in
  // sub-matches of first match :
  //   [Some("handle<<"), Some("handle"), Some("<<"), Some("::"), Some("++"), Some("MyCounter")]
  // splits:
  //   ["more ", "handle<<", "handle", "<<", "::", "++", "MyCounter", " more"]

  // 2) multiple handles | one counter
  // ---------------------------------

  // "more handle1<<handle2<<::++MyCounter more" will result in
  // content of first match : (only diff between first case)
  //    \"handle2<<handle1<<::++Counter\"
  // sub-matches of first match :
  //   [Some("handle2<<"), Some("handle2"), Some("<<"), Some("::"), Some("++"), Some   ("MyCounter")]
  // splits:
  //   ["more ", "handle2<<", "handle2", "<<", "::", "++", "MyCounter", " more"]

  // 3) 0 handles | one counter
  // --------------------------

  // "more ::++MyCounter more" will result in
  // sub-matches of first match :
  //   [None, None, None, Some("::"), Some("++"), Some   ("MyCounter")]
  // splits:
  //   ["more ", "", "", "", "::", "++", "MyCounter", " more"]

  // 4) x handle | multiple counters + random text
  // ---------------------------------------------

  // "more handle<<::++MyCounter-::--HisCounter more" will result in
  // ** content of first match: handle<<::++MyCounter-::--HisCounter

  // sub-matches of first match :
  //   [Some("handle<<"), Some("handle"), Some("<<"), Some("::"), Some("++"), Some("MyCounter"), Some("-::--HisCounter"), Some("-"), Some("::"), Some("--"), Some("HisCounter")]

  // splits:
  //   ["", "handle<<", "handle", "<<", "::", "++", "MyCounter", "-::--HisCounter", "-", "::", "--", "HisCounter", " more"]

  // if there are multiple appearances of last regex part - only last one will be in splits and matches . so we need to use match content to get all of them

  let #(_, re) = regexes
  let matches = regexp.scan(re, content)
  let splits = regexp.split(re, content)
  use error <- on.error(handle_matches(matches, splits, counters, regexes))
  Error(DesugaringError(blame, error))
}

fn update_line(
  line: Line,
  counters: CounterDict,
  regexes: #(Regexp, Regexp),
) -> Result(
  #(Line, CounterDict, List(HandleAssignment)),
  DesugaringError,
) {
  use #(content, counters, handles) <- on.ok(
    substitute_counters_and_generate_handle_assignments(
      line.blame,
      line.content,
      counters,
      regexes,
    )
  )
  Ok(#(Line(..line, content: content), counters, handles))
}

fn update_lines(
  lines: List(Line),
  counters: CounterDict,
  regexes: #(Regexp, Regexp),
) -> Result(
  #(List(Line), CounterDict, List(HandleAssignment)),
  DesugaringError,
) {
  lines
  |> list.try_fold(
    #([], counters, []),
    fn(acc, content) {
      let #(lines, counters, handles) = acc
      use #(updated_line, updated_counters, new_handles) <- on.ok(
        update_line(content, counters, regexes)
      )
      Ok(#(
        [updated_line, ..lines],
        updated_counters,
        list.flatten([handles, new_handles]),
      ))
    }
  )
  |> result.map(fn(acc) { #(acc.0 |> list.reverse, acc.1, acc.2) })
}

fn handle_assignment_attrs_from_handle_assignments(
  handles: List(HandleAssignment),
) -> List(Attr) {
  handles
  |> list.map(fn(handle) {
    let #(name, value) = handle
    Attr(desugarer_blame(301), "handle", name <> " " <> value)
  })
}

fn take_existing_counters(
  current: CounterDict,
  new: CounterDict,
) -> CounterDict {
  new
  |> dict.filter(fn(k, _) { dict.has_key(current, k) })
}

fn handle_non_unary_att_value(
  attr: Attr,
) -> Result(#(String, Int, Int), DesugaringError) {
  let splits = string.split(attr.val, " ")

  use counter_name, rest <- on.lazy_empty_nonempty(
    splits,
    fn() { Error(DesugaringError(attr.blame, "counter must have a name")) },
  )

  use starting_value, rest <- on.lazy_empty_nonempty(
    rest,
    fn() { Ok(#(counter_name, 0, 1)) },
  )

  use starting_value <- on.error_ok(
    int.parse(starting_value),
    fn(_) { Error(DesugaringError(attr.blame, "counter starting value must be a number")) },
  )

  use step, rest <- on.lazy_empty_nonempty(
    rest,
    fn() { Ok(#(counter_name, starting_value, 1)) },
  )

  use step <- on.error_ok(
    int.parse(step),
    fn(_) { Error(DesugaringError(attr.blame, "counter starting value must be a number")) },
  )

  case list.is_empty(rest) {
    True -> Ok(#(counter_name, starting_value, step))
    False -> Error(DesugaringError(attr.blame, "extra arguments found after <counter_name> <starting_value> <step_value>"))
  }
}

fn handle_unary_att_value(
 attr: Attr,
) -> Result(#(String, String), DesugaringError) {
  let splits = string.split(attr.val, " ")
  case splits {
    [counter_name, unary_char] -> Ok(#(counter_name, unary_char))
    [counter_name] -> Ok(#(counter_name, "1"))
    [] -> Error(DesugaringError(attr.blame, "counter attr without name"))
    _ -> Error(DesugaringError(attr.blame, "too many arguments for unary-counter"))
  }
}

fn attr_key_is_counter(
  key: String
) -> Result(CounterType, Nil) {
  case key {
    "counter" -> Ok(Arabic)
    "roman-counter" -> Ok(Roman)
    "unary-counter" -> Ok(Unary(""))
    _ -> Error(Nil)
  }
}

fn read_counter_definition(
  attr: Attr,
) -> Result(Option(#(String, CounterInfo)), DesugaringError) {
  use counter_type <- on.error_ok(
    attr_key_is_counter(attr.key),
    fn(_) { Ok(None) },
  )

  case counter_type {
    Unary(_) -> {
      use #(counter_name, unary_char) <- on.ok(handle_unary_att_value(attr))
      Ok(Some(#(counter_name, CounterInfo(Unary(unary_char), 0, 1))))
    }
    _ -> {
      use #(counter_name, initial_value, step) <- on.ok(handle_non_unary_att_value(attr))
      Ok(Some(#(counter_name, CounterInfo(counter_type, initial_value, step))))
    }
  }
}

fn fancy_one_attr_processor(
  attr: Attr,
  counters: CounterDict,
  regexes: #(Regexp, Regexp),
) -> Result(
  #(Attr, CounterDict, List(HandleAssignment)),
  DesugaringError,
) {
  let Attr(blame, original_key, val) = attr

  use #(key, counters, assignments1) <- on.ok(
    substitute_counters_and_generate_handle_assignments(
      blame,
      original_key,
      counters,
      regexes,
    ),
  )

  let assert True = key == string.trim(key)

  use <- on.true_false(
    key == "",
    Error(DesugaringError(
      blame,
      "empty key after processing counters; original key: '" <> original_key <> "'",
    )),
  )

  use #(val, counters, assignments2) <- on.ok(
    substitute_counters_and_generate_handle_assignments(
      blame,
      val,
      counters,
      regexes,
    ),
  )

  Ok(#(
    Attr(blame, key, val),
    counters,
    list.flatten([assignments1, assignments2]),
  ))
}

fn fancy_attr_processor(
  already_processed: List(Attr),
  yet_to_be_processed: List(Attr),
  counters: CounterDict,
  regexes: #(Regexp, Regexp),
) -> Result(#(List(Attr), CounterDict), DesugaringError) {
  case yet_to_be_processed {
    [] -> Ok(#(already_processed |> list.reverse, counters))
    [next, ..rest] -> {
      use #(next, counters, assignments) <- on.ok(
        fancy_one_attr_processor(next, counters, regexes),
      )

      let assignment_attrs =
        list.map(assignments, fn(handle_assignment) {
          let #(handle_name, handle_value) = handle_assignment
          Attr(next.blame, "handle", handle_name <> " " <> handle_value)
        })

      use new_counter <- on.ok(read_counter_definition(next))
      let counters = case new_counter {
        None -> counters
        Some(#(key, value)) -> dict.insert(counters, key, value)
      }

      let already_processed =
        list.flatten([
          assignment_attrs |> list.reverse,
          [next],
          already_processed,
        ])

      fancy_attr_processor(
        already_processed,
        rest,
        counters,
        regexes,
      )
    }
  }
}

type State = #(CounterDict, List(HandleAssignment))

fn v_before_transforming_children(
  vxml: VXML,
  state: State,
  regexes: #(Regexp, Regexp),
) -> Result(#(VXML, State), DesugaringError) {
  let assert V(b, t, attrs, c) = vxml
  let #(counters, handles) = state

  use #(attrs, counters) <- on.ok(fancy_attr_processor(
    [],
    attrs,
    counters,
    regexes,
  ))

  Ok(#(V(b, t, attrs, c), #(counters, handles)))
}

fn t_nodemap(
  vxml: VXML,
  state: State,
  regexes: #(Regexp, Regexp),
) -> Result(#(VXML, State), DesugaringError) {
  let assert T(blame, contents) = vxml
  let #(counters, old_handles) = state

  use #(contents, updated_counters, new_handles) <- on.ok(
    update_lines(contents, counters, regexes),
  )

  use <- on.some_none(
    infra.get_contained(new_handles, old_handles),
    fn(old_handle) {
      Error(DesugaringError(
        blame,
        "found previously-defined handle: " <> ins(old_handle),
      ))
    },
  )

  Ok(
    #(
      T(blame, contents),
      #(
        updated_counters,
        list.flatten([old_handles, new_handles]),
      )
    ),
  )
}

fn v_after_transforming_children(
  vxml: VXML,
  state_before: State,
  state_after: State,
) -> Result(#(VXML, State), DesugaringError) {
  let assert V(blame, tag, attrs, children) = vxml
  let #(counters_before, handles_before) = state_before
  let #(counters_after, handles_after) = state_after

  let handles_from_our_children =
    list.filter(handles_after, fn(h) { !list.contains(handles_before, h) })

  let attrs =
    list.append(
      attrs,
      handle_assignment_attrs_from_handle_assignments(
        handles_from_our_children,
      ),
    )

  let counters = take_existing_counters(counters_before, counters_after)

  Ok(#(V(blame, tag, attrs, children), #(counters, handles_before)))
}

fn our_two_regexes() -> #(Regexp, Regexp) {
  let any_number_of_handle_assignments = "(([\\w\\^-]+)(<<))*"

  let counter_prefix_and_counter =
    "("
    <> loud.regex_string
    <> "|"
    <> soft.regex_string
    <> ")("
    <> increment.regex_string
    <> "|"
    <> decrement.regex_string
    <> "|"
    <> no_change.regex_string
    <> ")(\\w+)"

  let any_number_of_counter_prefixes_and_counters_prefaced_by_punctuation =
    "((-|_|.|:|;|::|,)" <> counter_prefix_and_counter <> ")*"

  let assert Ok(big) =
    regexp.from_string(
      any_number_of_handle_assignments
      <> counter_prefix_and_counter
      <> any_number_of_counter_prefixes_and_counters_prefaced_by_punctuation,
    )

  let assert Ok(small) = regexp.from_string(counter_prefix_and_counter)

  #(small, big)
}

fn nodemap_factory(_: InnerParam) -> n2t.OneToOneBeforeAndAfterStatefulNodeMap(State) {
  let regexes = our_two_regexes()
  n2t.OneToOneBeforeAndAfterStatefulNodeMap(
    v_before_transforming_children: fn(vxml, state) { v_before_transforming_children(vxml, state, regexes) },
    v_after_transforming_children: v_after_transforming_children,
    t_nodemap: fn(vxml, state) { t_nodemap(vxml, state, regexes) },
  )
}

fn transform_factory(inner: InnerParam) -> infra.DesugarerTransform {
  n2t.one_to_one_before_and_after_stateful_nodemap_2_desugarer_transform(
    nodemap_factory(inner),
    #(dict.from_list([]), []),
  )
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(param)
}

type Param = Nil
type InnerParam = Nil

pub const name = "counters_substitute_and_assign_handles"
fn desugarer_blame(line_no: Int) { bl.Des([], name, line_no) }

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// Substitutes counters by their numerical
/// value converted to string form and assigns those
/// values to prefixed handles.
///
/// If a counter named 'MyCounterName' is defined by
/// an ancestor, replaces strings of the form
///
/// \<aa>\<bb>MyCounterName
///
/// where
///
/// \<aa> == \"::\"|\"..\" indicates whether
/// the counter occurrence should be echoed as a
/// string appearing in the document or not (\"::\" == echo,
/// \"..\" == suppress), and where
///
/// \<bb> ==  \"++\"|\"--\"|\"øø\" indicates whether
/// the counter should be incremented, decremented, or
/// neither prior to possible insertion,
///
/// by the appropriate replacement string (possibly
/// none), and assigns handles coming to the left
/// using the '<<' assignment, e.g.,
///
/// handleName<<..++MyCounterName
///
/// would assign the stringified incremented value
/// of MyCounterName to handle 'handleName' without
/// echoing the value to the document, whereas
///
/// handleName<<::++MyCounterName
///
/// will do the same but also insert the new counter
/// value at that point in the document.
///
/// The computed handle assignments are recorded as
/// attrs of the form
///
/// handle_\<handleName> <counterValue>
///
/// on the parent tag to be later used by the
/// 'handles_generate_dictionary' desugarer
pub fn constructor() -> Desugarer {
  Desugarer(
    name: name,
    stringified_param: option.None,
    stringified_outside: option.None,
    transform: case param_to_inner_param(Nil) {
      Error(error) -> fn(_) { Error(error) }
      Ok(inner) -> transform_factory(inner)
    },
  )
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
fn assertive_tests_data() -> List(infra.AssertiveTestDataNoParam) {
  [
    infra.AssertiveTestDataNoParam(
      source:   "
                <> root
                  counter=QCounter -3
                  <>
                    \"::--QCounter;::--QCounter\"
                ",
      expected: "
                <> root
                  counter=QCounter -3
                  <>
                    \"-4;-5\"
                ",
    ),
    infra.AssertiveTestDataNoParam(
      source:   "
                <> root
                  counter=QCounter -3
                  <>
                    \"t<<::--QCounter;..--QCounter\"
                    \"u<<..--QCounter;::--QCounter\"
                    \"GooseMan..--QCounter;::--QCounter;..--QCounter;..--QCounter.::--QCounter@hoverboard\"
                ",
      expected: "
                <> root
                  counter=QCounter -3
                  handle=t -4;-5
                  handle=u -6;-7
                  <>
                    \"-4\"
                    \"-7\"
                    \"GooseMan-9.-12@hoverboard\"
                ",
    ),
    infra.AssertiveTestDataNoParam(
      source:   "
                <> root
                  counter=QCounter -3
                  <>
                    \"z<<::++QCounter t<<..øøQCounter\"
                    \"w<<::--QCounter\"
                    \"b<<a<<::++QCounter.::++QCounter f<<g<<..øøQCounter\"
                ",
      expected: "
                <> root
                  counter=QCounter -3
                  handle=z -2
                  handle=t -2
                  handle=w -3
                  handle=b -2.-1
                  handle=a -2.-1
                  handle=f -1
                  handle=g -1
                  <>
                    \"-2 \"
                    \"-3\"
                    \"-2.-1 \"
                ",
    ),
    infra.AssertiveTestDataNoParam(
      source:   "
                <> root
                  counter=my_counter 5
                  <>
                    \"first-handle<<::++my_counter\"
                    \"second-handle<<::--my_counter\"
                    \"third-handle<<::++my_counter.::++my_counter\"
                ",
      expected: "
                <> root
                  counter=my_counter 5
                  handle=first-handle 6
                  handle=second-handle 5
                  handle=third-handle 6.7
                  <>
                    \"6\"
                    \"5\"
                    \"6.7\"
                ",
    ),
    infra.AssertiveTestDataNoParam(
      source:   "
                <> root
                  counter=TestCounter 1
                  <>
                    \"handle^with^caret<<::++TestCounter\"
                    \"another^handle<<::--TestCounter\"
                ",
      expected: "
                <> root
                  counter=TestCounter 1
                  handle=handle^with^caret 2
                  handle=another^handle 1
                  <>
                    \"2\"
                    \"1\"
                ",
    ),
  ]
}

pub fn assertive_tests() {
  infra.assertive_test_collection_from_data_no_param(name, assertive_tests_data(), constructor)
}
