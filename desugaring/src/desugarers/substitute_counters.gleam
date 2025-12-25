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
import blame.{type Blame}
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

type CounterDict =
  Dict(String, CounterInfo)

type State =
  CounterDict

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
    _ -> {
      echo mutation
      panic as "bad mutation"
    }
  }
}

fn render_info(
  info: CounterInfo
) -> String {
  case info.counter_type {
    Arabic -> ins(info.value)
    Roman -> roman.int_to_roman(info.value) |> option.unwrap([]) |> roman.roman_to_string()
    Unary(c) -> string.repeat(c, info.value)
  }
}

fn process_regex_groups(
  blame: Blame,
  counters: CounterDict,
  a: String,
  b: String,
  c: String,
) -> Result(#(String, CounterDict), DesugaringError) {
  use info <- on.error_ok(
    dict.get(counters, c),
    fn(_) { Error(DesugaringError(blame, "undefined counter: " <> c)) },
  )
  let info = update_info(info, b)
  let render = case a {
    _ if a == loud.string -> render_info(info)
    _ if a == soft.string -> ""
    _ -> panic
  }
  Ok(#(render, dict.insert(counters, c, info)))
}

fn process_splits(
  blame: Blame,
  already_processed: List(String),
  counters: CounterDict,
  splits: List(String),
) -> Result(#(List(String), CounterDict), DesugaringError) {
  let assert [first, ..splits] = splits
  case splits {
    [] -> Ok(#(
      [first, ..already_processed],
      counters,
    ))
    [a, b, c, ..splits] -> {
      use #(render, counters) <- on.ok(
        process_regex_groups(blame, counters, a, b, c)
      )
      process_splits(
        blame,
        [render, first, ..already_processed],
        counters,
        splits,
      )
    }
    _ -> panic
  }
}

fn process_string(
  blame: Blame,
  content: String,
  counters: CounterDict,
  inner: InnerParam,
) -> Result(#(String, CounterDict), DesugaringError) {
  use <- on.true_false(
    content == "",
    fn() { Ok(#("", counters)) },
  )
  let splits = regexp.split(inner, content)
  use #(strings, counters) <- on.ok(
    process_splits(blame, [], counters, splits)
  )
  Ok(#(
    strings |> list.reverse |> string.join(""),
    counters,
  ))
}

fn update_lines(
  lines: List(Line),
  counters: CounterDict,
  inner: InnerParam,
) -> Result(
  #(List(Line), CounterDict),
  DesugaringError,
) {
  // nb: tried doing an early-return test here on
  // 'lines' to improve speed, didn't help much
  lines
  |> list.try_fold(
    #([], counters),
    fn(acc, line) {
      let #(lines, counters) = acc
      use #(content, counters) <- on.ok(
        process_string(line.blame, line.content, counters, inner)
      )
      Ok(#([Line(..line, content: content), ..lines], counters))
    }
  )
  |> result.map(fn(acc) { #(acc.0 |> list.reverse, acc.1) })
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

  use counter_name, rest <- on.empty_nonempty(
    splits,
    fn() { Error(DesugaringError(attr.blame, "counter must have a name")) },
  )

  use starting_value, rest <- on.empty_nonempty(
    rest,
    fn() { Ok(#(counter_name, 0, 1)) },
  )

  use starting_value <- on.error_ok(
    int.parse(starting_value),
    fn(_) { Error(DesugaringError(attr.blame, "counter starting value must be a number")) },
  )

  use step, rest <- on.empty_nonempty(
    rest,
    fn() { Ok(#(counter_name, starting_value, 1)) },
  )

  use step <- on.error_ok(
    int.parse(step),
    fn(_) { Error(DesugaringError(attr.blame, "counter step size must be a number")) },
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
  inner: InnerParam,
) -> Result(
  #(Attr, CounterDict),
  DesugaringError,
) {
  let Attr(blame, original_key, val) = attr

  use #(key, counters) <- on.ok(
    process_string(
      blame,
      original_key,
      counters,
      inner,
    ),
  )

  let assert True = key == string.trim(key)

  use <- on.true_false(
    key == "",
    fn() { Error(DesugaringError(
      blame,
      "empty key after processing counters; original key: '" <> original_key <> "'",
    )) },
  )

  use #(val, counters) <- on.ok(
    process_string(
      blame,
      val,
      counters,
      inner,
    ),
  )

  Ok(#(
    Attr(blame, key, val),
    counters,
  ))
}

fn fancy_attr_processor(
  already_processed: List(Attr),
  yet_to_be_processed: List(Attr),
  counters: CounterDict,
  inner: InnerParam,
) -> Result(#(List(Attr), CounterDict), DesugaringError) {
  use next, rest <- on.empty_nonempty(
    yet_to_be_processed,
    fn() { Ok(#(already_processed |> list.reverse, counters)) },
  )

  use #(next, counters) <- on.ok(
    fancy_one_attr_processor(next, counters, inner)
  )

  use new_counter <- on.ok(read_counter_definition(next))
  let counters = case new_counter {
    None -> counters
    Some(#(key, value)) -> dict.insert(counters, key, value)
  }

  let already_processed = [next, ..already_processed]

  fancy_attr_processor(
    already_processed,
    rest,
    counters,
    inner,
  )
}

fn v_before_transforming_children(
  vxml: VXML,
  state: State,
  inner: InnerParam,
) -> Result(#(VXML, State), DesugaringError) {
  let assert V(b, t, attrs, c) = vxml
  let counters = state

  use #(attrs, counters) <- on.ok(fancy_attr_processor(
    [],
    attrs,
    counters,
    inner,
  ))

  Ok(#(V(b, t, attrs, c), counters))
}

fn t_nodemap(
  vxml: VXML,
  state: State,
  inner: InnerParam,
) -> Result(#(VXML, State), DesugaringError) {
  let assert T(blame, lines) = vxml
  let counters = state
  use #(lines, updated_counters) <- on.ok(
    update_lines(lines, counters, inner),
  )
  #(T(blame, lines), updated_counters)
  |> Ok
}

fn v_after_transforming_children(
  vxml: VXML,
  state_before: State,
  state_after: State,
) -> Result(#(VXML, State), DesugaringError) {
  let assert V(blame, tag, attrs, children) = vxml
  let counters_before = state_before
  let counters_after = state_after
  let counters = take_existing_counters(counters_before, counters_after)
  Ok(#(V(blame, tag, attrs, children), counters))
}

fn counter_regex() -> Regexp {
  let assert Ok(re) = {
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
  } |> regexp.from_string

  re
}

fn nodemap_factory(inner: InnerParam) -> n2t.OneToOneBeforeAndAfterStatefulNodeMap(State) {
  n2t.OneToOneBeforeAndAfterStatefulNodeMap(
    v_before_transforming_children: fn(vxml, state) { v_before_transforming_children(vxml, state, inner) },
    v_after_transforming_children: v_after_transforming_children,
    t_nodemap: fn(vxml, state) { t_nodemap(vxml, state, inner) },
  )
}

fn transform_factory(inner: InnerParam) -> infra.DesugarerTransform {
  n2t.one_to_one_before_and_after_stateful_nodemap_2_desugarer_transform(
    nodemap_factory(inner),
    dict.from_list([]),
  )
}

fn param_to_inner_param(_: Param) -> Result(InnerParam, DesugaringError) {
  Ok(counter_regex())
}

type Param = Nil
type InnerParam = Regexp

pub const name = "substitute_counters"
// fn desugarer_blame(line_no: Int) { bl.Des([], name, line_no) }

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// Substitutes strings of the form
/// 
///          (::|..)(++|--|øø)<counterName>
///
/// inside text lines and attribute values by string
/// value of the counter, while incrementing/decrementing
/// counters along the way.
/// 
/// The counter must have initialized by the time
/// it's used or else a DesugaringError will occur.
/// 
/// E.g., here is a correct use of a counter:
/// 
/// <> Chapter
///     counter=ExerciseCounter
///     <> Section
///         number=::--SectionCounter
/// 
/// After the desugarer is run, this would become:
///
/// <> Chapter
///     counter=ExerciseCounter
///     <> Section
///         number=-1
/// 
/// The second capturing group (++|--|øø)
/// determines whether a counter is incremented,
/// decremented, or kept equal at a point (according
/// to its step size), whereas the first capturing
/// group determines the string value of the counter
/// is echoed '::' or silenced '..', i.e., inserted
/// or not into the document at that point. In
/// partuclar, a counter of the form
/// 
///        ..øø<counterName>
/// 
/// has no effect on the document.
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
                    'aa::--QCounter;bb'
                ",
      expected: "
                <> root
                  counter=QCounter -3
                  <>
                    'aa-4;bb'
                ",
    ),
    infra.AssertiveTestDataNoParam(
      source:   "
                <> root
                  counter=QCounter -3
                  <>
                    '::--QCounter;..--QCounter'
                    '..--QCounter;::--QCounter'
                    'GooseMan..--QCounter;::--QCounter;..--QCounter;..--QCounter.::--QCounter@hoverboard'
                ",
      expected: "
                <> root
                  counter=QCounter -3
                  <>
                    '-4;'
                    ';-7'
                    'GooseMan;-9;;.-12@hoverboard'
                ",
    ),
    infra.AssertiveTestDataNoParam(
      source:   "
                <> root
                  counter=QCounter -3
                  <>
                    '::++QCounter ..øøQCounter'
                    '::--QCounter'
                    '::++QCounter.::++QCounter K..øøQCounter&W'
                ",
      expected: "
                <> root
                  counter=QCounter -3
                  <>
                    '-2 '
                    '-3'
                    '-2.-1 K&W'
                ",
    ),
    infra.AssertiveTestDataNoParam(
      source:   "
                <> root
                  counter=my_counter 5 2
                  <>
                    '::++my_counter'
                    '::--my_counter'
                    '::++my_counter.::++my_counter'
                ",
      expected: "
                <> root
                  counter=my_counter 5 2
                  <>
                    '7'
                    '5'
                    '7.9'
                ",
    ),
    infra.AssertiveTestDataNoParam(
      source:   "
                <> root
                  counter=TestCounter -1
                  <>
                    '::++TestCounter'
                    '::--TestCounter::--TestCounter'
                ",
      expected: "
                <> root
                  counter=TestCounter -1
                  <>
                    '0'
                    '-1-2'
                ",
    ),
  ]
}

pub fn assertive_tests() {
  infra.assertive_test_collection_from_data_no_param(name, assertive_tests_data(), constructor)
}
