import gleam/dict.{type Dict}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/regexp.{type Match, type Regexp, Match}
import gleam/string.{inspect as ins}
import blame.{type Blame}
import infrastructure.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
  type DesugaringWarning, Desugarer, DesugaringWarning,
} as infra
import nodemaps_2_desugarer_transforms as n2t
import vxml.{type Attr, type Line, type VXML, Line, T, V}

fn extract_handle_and_page_and_decoy(match: Match) -> #(String, Bool, Option(String)) {
  let assert Match(_, [_, option.Some(handle_name)]) = match
  let #(handle_name, page) = case string.split_once(handle_name, "#page") {
    Ok(#(before, after)) -> #(before <> after, True)
    _ -> #(handle_name, False)
  }
  let #(handle_name, decoy) = case string.split_once(handle_name, "#decoy:") {
    Ok(#(before, after)) -> #(before, option.Some(after))
    _ -> #(handle_name, None)
  }
  let handle_name = string.remove_suffix(handle_name, "##")
  #(handle_name, page, decoy)
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

fn substitution_text(
  handle_and_page_and_decoy: #(String, Bool, Option(String)),
  blame: Blame,
  fold_parens: Bool,
  state: State,
) -> #(String, List(DesugaringWarning)) {
  let #(handle_name, page, decoy) = handle_and_page_and_decoy
  let wrap = fn(s: String) -> String {
    case fold_parens {
      True -> "(" <> s <> ")"
      False -> s
    }
  }
  case dict.get(state.handles, handle_name) {
    Ok(#(page_by_default, value, id, target_path)) -> {
      let target = case page || page_by_default {
        True -> target_path
        False -> target_path <> "#" <> id
      }
      #("\\href{" <> target <> "}{" <> wrap(value) <> "}", [])
    }
    Error(_) -> {
      let warning =
        DesugaringWarning(blame, "handle '" <> handle_name <> "' is not assigned")
      case decoy {
        Some(decoy_value) -> #(
          "\\href{decoy-target-path#decoy-id}{" <> wrap(decoy_value) <> "}",
          [warning],
        )
        None -> #(wrap("undefined handle: " <> handle_name), [warning])
      }
    }
  }
}

fn rebuild(
  splits: List(String),
  matches: List(Match),
  blame: Blame,
  state: State,
) -> #(String, List(DesugaringWarning)) {
  case splits, matches {
    [last], [] -> #(last, [])
    [before, next, ..rest_splits], [m, ..rest_matches] -> {
      let fold = string.ends_with(before, "(") && string.starts_with(next, ")")
      let #(before, next) = case fold {
        True -> #(string.drop_end(before, 1), string.drop_start(next, 1))
        False -> #(before, next)
      }
      let #(sub_text, warnings) =
        substitution_text(extract_handle_and_page_and_decoy(m), blame, fold, state)
      let #(rest_text, rest_warnings) =
        rebuild([next, ..rest_splits], rest_matches, blame, state)
      #(before <> sub_text <> rest_text, infra.pour(warnings, rest_warnings))
    }
    _, _ -> panic as "splits/matches length mismatch in handles_substitute_inside_math"
  }
}

fn process_line(
  line: Line,
  state: State,
  inner: InnerParam,
) -> #(Line, List(DesugaringWarning)) {
  let Line(blame, content) = line
  case regexp.scan(inner.1, content) {
    [] -> #(line, [])
    matches -> {
      let splits =
        regexp.split(inner.1, content)
        |> augment_to_1_mod_3
        |> retain_0_mod_3
      let #(new_content, warnings) = rebuild(splits, matches, blame, state)
      #(Line(blame, new_content), warnings)
    }
  }
}

fn process_lines(
  lines: List(Line),
  state: State,
  inner: InnerParam,
) -> #(List(Line), List(DesugaringWarning)) {
  let #(new_lines, warnings_lists) =
    lines
    |> list.map(process_line(_, state, inner))
    |> list.unzip
  #(new_lines, warnings_lists |> list.flatten)
}

fn grand_wrapper_load(state: State, attrs: List(Attr)) -> State {
  let #(handle_attrs, _) = infra.attrs_extract_key_occurrences(attrs, "handle")

  let handles =
    list.fold(handle_attrs, dict.new(), fn(acc, attr) {
      let assert [handle_name, page, value, id, path] =
        attr.val |> string.split("|")
      let page = case page {
        "#page" -> True
        "" -> False
        _ -> panic as "malformed GrandWrapper dictionary"
      }
      dict.insert(acc, handle_name, #(page, value, id, path))
    })

  State(..state, handles: handles)
}

fn t_transform(
  vxml: VXML,
  state: State,
  inner: InnerParam,
) -> Result(#(VXML, State, List(DesugaringWarning)), DesugaringError) {
  let assert T(blame, lines) = vxml
  case state.inside_math {
    False -> Ok(#(vxml, state, []))
    True -> {
      let #(new_lines, warnings) = process_lines(lines, state, inner)
      Ok(#(T(blame, new_lines), state, warnings))
    }
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
    _ -> state
  }
  let state = case state.inside_math || !list.contains(inner.0, tag) {
    True -> state
    False -> State(..state, inside_math: True)
  }
  Ok(#(vxml, state, []))
}

fn v_after_transform(
  vxml: VXML,
  original_state: State,
  latest_state: State,
) -> Result(#(VXML, State, List(DesugaringWarning)), DesugaringError) {
  let exit_state = State(..latest_state, inside_math: original_state.inside_math)
  Ok(#(vxml, exit_state, []))
}

fn nodemap_factory(
  inner: InnerParam,
) -> n2t.FancyOneToOneBeforeAndAfterStatefulNodemapWithWarnings(State) {
  n2t.FancyOneToOneBeforeAndAfterStatefulNodemapWithWarnings(
    v_before_transforming_children: fn(vxml, _, _, _, _, state) {
      v_before_transform(vxml, state, inner)
    },
    v_after_transforming_children: fn(vxml, _, _, _, _, original_state, latest_state) {
      v_after_transform(vxml, original_state, latest_state)
    },
    t_nodemap: fn(vxml, _, _, _, _, state) { t_transform(vxml, state, inner) },
  )
}

fn transform_factory(inner: InnerParam) -> DesugarerTransform {
  n2t.fancy_one_to_one_before_and_after_stateful_nodemap_with_warnings_2_desugarer_transform(
    nodemap_factory(inner),
    State(dict.new(), False),
  )
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  let assert Ok(handles_regexp) =
    regexp.from_string("(>>)([\\w^.:'-]+[\\w'](?:#page)?(?:#decoy:[0-9]+)?(?:##)?)")

  #(param, handles_regexp) |> Ok
}

type HandlesDict = Dict(String, #(Bool,     String,   String,   String))
//                      ↖         ↖         ↖         ↖         ↖
//                      handle    #page-by  value     id        path
//                               #default
//                                option

type State {
  State(handles: HandlesDict, inside_math: Bool)
}

type Param = List(String)
//           ↖
//           tags (typically ["Math", "MathBlock"]) whose T-node
//           descendants should have >>handle occurrences substituted

type InnerParam = #(List(String), Regexp)

pub const name = "handles_substitute_inside_math"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// Expects a document with root 'GrandWrapper' as
/// produced by handles_generate_dictionary_and_id_list,
/// whose attrs comprise key-value pairs of the form
///
/// handle=handle_name|#page-or-empty|value|id|path
///
/// Unlike handles_substitute_and_fix_nonlocal_id_links,
/// this desugarer does not turn >>handle_name occurrences
/// into V-node links: instead, inside any descendant of a
/// tag named in the Param list (typically "Math" and
/// "MathBlock"), it substitutes >>handle_name occurrences
/// in place, as plain text, with a LaTeX
///
/// \href{<target_path>}{<value>}
///
/// fragment, so that the substitution can be safely
/// rendered by MathJax alongside surrounding LaTeX source.
/// <target_path> is <path> when the occurrence (or the
/// handle itself) carries a #page suffix, and
/// <path>#<id> otherwise.
///
/// If the >>handle_name occurrence is immediately preceded
/// by '(' and immediately followed by ')' (no whitespace),
/// both parentheses are absorbed into the \href value
/// (\href{...}{(<value>)}) instead of being left outside of it.
///
/// If handle_name is not assigned, falls back to its
/// #decoy:<value> suffix if present (building a
/// 'decoy-target-path#decoy-id' href), or otherwise
/// substitutes a plain 'undefined handle: <handle_name>'
/// text, emitting a DesugaringWarning in both cases.
///
/// Does not touch text outside of the Param-listed tags,
/// and does not destroy or otherwise alter the GrandWrapper
/// node, leaving it intact for a later desugarer (typically
/// handles_substitute_and_fix_nonlocal_id_links) to consume.
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
      param: ["Math", "MathBlock"],
      source: "
        <> GrandWrapper
          handle=some_handle||2|eq-id|./ch1.html
          <> root
            <> Chapter
              <> Math
                <>
                  '(>>some_handle) a + b = 2'
      ",
      expected: "
        <> GrandWrapper
          handle=some_handle||2|eq-id|./ch1.html
          <> root
            <> Chapter
              <> Math
                <>
                  '\\href{./ch1.html#eq-id}{(2)} a + b = 2'
      ",
    ),
    infra.AssertiveTestData(
      param: ["Math", "MathBlock"],
      source: "
        <> GrandWrapper
          handle=some_handle||2|eq-id|./ch1.html
          <> root
            <> Chapter
              <> Math
                <>
                  'see >>some_handle for details'
      ",
      expected: "
        <> GrandWrapper
          handle=some_handle||2|eq-id|./ch1.html
          <> root
            <> Chapter
              <> Math
                <>
                  'see \\href{./ch1.html#eq-id}{2} for details'
      ",
    ),
    infra.AssertiveTestData(
      param: ["Math", "MathBlock"],
      source: "
        <> GrandWrapper
          handle=some_handle||2|eq-id|./ch1.html
          <> root
            <> Chapter
              <> MathBlock
                <>
                  'see >>some_handle#page for the page'
      ",
      expected: "
        <> GrandWrapper
          handle=some_handle||2|eq-id|./ch1.html
          <> root
            <> Chapter
              <> MathBlock
                <>
                  'see \\href{./ch1.html}{2} for the page'
      ",
    ),
    infra.AssertiveTestData(
      param: ["Math", "MathBlock"],
      source: "
        <> GrandWrapper
          handle=other||2|eq-id|./ch1.html
          <> root
            <> Chapter
              <> Math
                <>
                  '(>>missing#decoy:26) a + b'
      ",
      expected: "
        <> GrandWrapper
          handle=other||2|eq-id|./ch1.html
          <> root
            <> Chapter
              <> Math
                <>
                  '\\href{decoy-target-path#decoy-id}{(26)} a + b'
      ",
    ),
    infra.AssertiveTestData(
      param: ["Math", "MathBlock"],
      source: "
        <> GrandWrapper
          handle=other||2|eq-id|./ch1.html
          <> root
            <> Chapter
              <> Math
                <>
                  '>>missing a + b'
      ",
      expected: "
        <> GrandWrapper
          handle=other||2|eq-id|./ch1.html
          <> root
            <> Chapter
              <> Math
                <>
                  'undefined handle: missing a + b'
      ",
    ),
    infra.AssertiveTestData(
      param: ["Math", "MathBlock"],
      source: "
        <> GrandWrapper
          handle=some_handle||2|eq-id|./ch1.html
          <> root
            <> Chapter
              <>
                '(>>some_handle) is outside of math'
      ",
      expected: "
        <> GrandWrapper
          handle=some_handle||2|eq-id|./ch1.html
          <> root
            <> Chapter
              <>
                '(>>some_handle) is outside of math'
      ",
    ),
  ]
}

pub fn assertive_tests() {
  infra.assertive_test_collection_from_data(name, assertive_tests_data(), constructor)
}
