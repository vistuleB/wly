import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/regexp
import gleam/result
import gleam/string.{inspect as ins}
import infrastructure.{type Desugarer, Desugarer, type DesugarerTransform, type DesugaringError, DesugaringError} as infra
import nodemaps_2_desugarer_transforms as n2t
import vxml.{type VXML, T, V, Attr, type Line, Line}
import blame.{type Blame} as bl
import on

type PatternToken {
  EndT
  StartT
  Space
  Word(String)    // (does not contain whitespace)
  ContentVar(Int)
  A(
    tag: String,
    classes: String,
    href: Int,
    children: LinkPattern,
  )
}

type LinkPattern =
  List(PatternToken)

type MatchData {
  MatchData(
    href_var_dict: Dict(Int, VXML),
    content_var_dict: Dict(Int, List(VXML)),
  )
}

fn detokenize_maybe(
  children: List(VXML),
  accumulated_lines: List(Line),
  accumulated_nodes: List(VXML),
) -> List(VXML) {
  let append_word_to_accumlated_contents = fn(
    blame: Blame,
    word: String,
  ) -> List(Line) {
    case accumulated_lines {
      [first, ..rest] -> [Line(first.blame, first.content <> word), ..rest]
      _ -> [Line(blame, word)]
    }
  }

  case children {
    [] -> {
      let assert [] = accumulated_lines
      accumulated_nodes |> list.reverse |> infra.last_to_first_concatenation
    }

    [first, ..rest] -> {
      case first {
        V(blame, "__StartTokenizedT", _, _) -> {
          let assert [] = accumulated_lines
          let accumulated_lines = [Line(blame, "")]
          detokenize_maybe(rest, accumulated_lines, accumulated_nodes)
        }

        V(blame, "__OneWord", attrs, _) -> {
          let assert [_, ..] = accumulated_lines
          let assert [Attr(_, "val", word)] = attrs
          let accumulated_lines = append_word_to_accumlated_contents(blame, word)
          detokenize_maybe(rest, accumulated_lines, accumulated_nodes)
        }

        V(blame, "__OneSpace", _, _) -> {
          let assert [_, ..] = accumulated_lines
          let accumulated_lines = append_word_to_accumlated_contents(blame, " ")
          detokenize_maybe(rest, accumulated_lines, accumulated_nodes)
        }

        V(blame, "__OneNewLine", _, _) -> {
          let assert [_, ..] = accumulated_lines
          let accumulated_lines = [Line(blame, ""), ..accumulated_lines]
          detokenize_maybe(rest, accumulated_lines, accumulated_nodes)
        }

        V(blame, "__EndTokenizedT", _, _) -> {
          let assert [_, ..] = accumulated_lines
          let accumulated_lines = append_word_to_accumlated_contents(blame, "")
          detokenize_maybe(rest, [], [T(blame, accumulated_lines |> list.reverse), ..accumulated_nodes])
        }

        V(_, _, _, children) -> case infra.v_has_attr_with_key(first, "href") {
          True -> {
            let children = detokenize_maybe(children, [], [])
            detokenize_maybe(rest, [], [V(..first, children: children), ..accumulated_nodes])
          }
          False -> detokenize_maybe(rest, [], [first, ..accumulated_nodes])
        }

        T(_, _) -> {
          let assert [] = accumulated_lines
          panic as "how did T not become tokenized"
        }
      }
    }
  }
}

fn generate_replacement_vxml_internal(
  already_ready: List(VXML),
  pattern: List(PatternToken),
  match_data: MatchData,
) -> List(VXML) {
  case pattern {
    [] -> already_ready |> list.reverse
    [p, ..pattern_rest] -> {
      case p {
        StartT -> generate_replacement_vxml_internal(
          [start_node(desugarer_blame(119)), ..already_ready],
          pattern_rest,
          match_data,
        )

        EndT -> generate_replacement_vxml_internal(
          [end_node(desugarer_blame(125)), ..already_ready],
          pattern_rest,
          match_data,
        )

        Space -> generate_replacement_vxml_internal(
          [space_node(desugarer_blame(131)), ..already_ready],
          pattern_rest,
          match_data,
        )

        Word(word) -> generate_replacement_vxml_internal(
          [word_node(desugarer_blame(137), word), ..already_ready],
          pattern_rest,
          match_data,
        )

        ContentVar(z) -> {
          let assert Ok(z_vxmls) = dict.get(match_data.content_var_dict, z)
          generate_replacement_vxml_internal(
            infra.pour(z_vxmls, already_ready),
            pattern_rest,
            match_data,
          )
        }

        A(_, classes, href_int, internal_pattern) -> {
          let assert Ok(vxml) = dict.get(match_data.href_var_dict, href_int)
          let assert V(blame, tag, attrs, _) = vxml
          let a_node = V(
            blame,
            tag,
            attrs |> infra.attrs_append_classes(blame, classes),
            generate_replacement_vxml_internal([], internal_pattern, match_data),
          )
          generate_replacement_vxml_internal(
            [a_node, ..already_ready],
            pattern_rest,
            match_data,
          )
        }
      }
    }
  }
}

fn fast_forward_past_spaces(
  atomized: List(VXML),
) -> List(VXML) {
  list.drop_while(atomized, infra.v_tag_is_one_of(_, ["__OneSpace", "__OneNewLine"]))
}

fn insert_new_content_key_val_into_match_data(
  match_data: MatchData,
  key: Int,
  val: List(VXML),
) -> MatchData {
  let c = match_data.content_var_dict
  let assert Error(Nil) = dict.get(c, key)
  let c = dict.insert(c, key, val)
  MatchData(..match_data, content_var_dict: c)
}

fn insert_new_href_key_val_into_match_data(
  match_data: MatchData,
  key: Int,
  val: VXML,
) -> MatchData {
  let c = match_data.href_var_dict
  let assert Error(Nil) = dict.get(c, key)
  let c = dict.insert(c, key, val)
  MatchData(..match_data, href_var_dict: c)
}

fn is_inner_text_token(
  vxml: VXML
) -> Bool {
  case vxml {
    T(_, _) -> False
    V(_, "__OneWord", _, _) -> True
    V(_, "__OneSpace", _, _) -> True
    V(_, "__OneNewLine", _, _) -> True
    _ -> False
  }
}

fn vxmls_dont_start_or_end_inside_text_mode(
  vxmls: List(VXML),
) -> Bool {
  case vxmls {
    [] -> True
    [first, ..] -> {
      let assert Ok(last) = list.last(vxmls)
      !{
        is_inner_text_token(first)
        || is_inner_text_token(last)
        || infra.is_v_and_tag_equals(first, "__EndT")
        || infra.is_v_and_tag_equals(last, "__StartT")
      }
    }
  }
}

fn match_internal(
  atomized: List(VXML),
  pattern: LinkPattern,
  match_data: MatchData,
) -> Option(#(MatchData, List(VXML))) {
  case pattern {
    [] -> {
      Some(#(match_data, atomized))
    }

    [EndT, ..pattern_rest] -> {
      case atomized {
        [V(_, "__EndTokenizedT", _, _), ..atomized_rest] ->
          match_internal(atomized_rest, pattern_rest, match_data)
        _ -> None
      }
    }

    [StartT, ..pattern_rest] -> {
      case atomized {
        [V(_, "__StartTokenizedT", _, _), ..atomized_rest] ->
          match_internal(atomized_rest, pattern_rest, match_data)
        _ -> None
      }
    }

    [ContentVar(content_int), ..pattern_rest] -> {
      let assert [] = pattern_rest
      let assert True = vxmls_dont_start_or_end_inside_text_mode(atomized)
      let match_data = insert_new_content_key_val_into_match_data(match_data, content_int, atomized)
      match_internal([], pattern_rest, match_data)
    }

    [Word(word), ..pattern_rest] -> {
      case atomized {
        [V(_, "__OneWord", _, _) as v, ..atomized_rest] -> {
          let assert Some(attr) = infra.v_first_attr_with_key(v, "val")
          case attr.val == word {
            True -> match_internal(atomized_rest, pattern_rest, match_data)
            False -> None
          }
        }
        _ -> None
      }
    }

    [Space, ..pattern_rest] -> {
      case atomized {
        [V(_, tag, _, _), ..atomized_rest] if tag == "__OneSpace" || tag == "__OneNewLine" ->
          match_internal(atomized_rest |> fast_forward_past_spaces, pattern_rest, match_data)
        _ -> None
      }
    }

    [A(_, _, href_int, pattern_internal), ..pattern_rest] -> {
      case atomized {
        [V(_, _, _, children) as v, ..atomized_rest] -> case infra.v_has_attr_with_key(v, "href") {
          True -> {
            let match_data = insert_new_href_key_val_into_match_data(match_data, href_int, v)
            case match_internal(children, pattern_internal, match_data) {
              // children must match in their entirety:
              Some(#(match_data, [])) -> match_internal(atomized_rest, pattern_rest, match_data)
              _ -> None
            }
          }
          False -> None
        }
        _ -> None
      }
    }
  }
}

fn match(atomized: List(VXML), pattern: LinkPattern) -> Option(#(MatchData, List(VXML))) {
  match_internal(atomized, pattern, MatchData(dict.new(), dict.new()))
}

fn generate_replacement_vxml(
  pattern: LinkPattern,
  match_data: MatchData,
) -> List(VXML) {
  generate_replacement_vxml_internal([], pattern, match_data)
}

fn match_until_end_internal(
  already_done: List(VXML),
  atomized: List(VXML),
  pattern1: LinkPattern,
  pattern2: LinkPattern,
) -> List(VXML) {
  case atomized {
    [] -> already_done |> list.reverse

    [first, ..rest] -> case match(atomized, pattern1) {
      None -> match_until_end_internal(
        [first, ..already_done],
        rest,
        pattern1,
        pattern2,
      )

      Some(#(match_data, rest)) -> {
        let replacement = generate_replacement_vxml(pattern2, match_data)
        match_until_end_internal(
          infra.pour(replacement, already_done),
          rest,
          pattern1,
          pattern2,
        )
      }
    }
  }
}

fn match_until_end(
  atomized: List(VXML),
  pattern1: LinkPattern,
  pattern2: LinkPattern,
) -> List(VXML) {
  match_until_end_internal([], atomized, pattern1, pattern2)
}

fn start_node(blame: Blame) {
  V(blame, "__StartTokenizedT", [], [])
}

fn word_node(blame: Blame, word: String) {
  V(blame, "__OneWord", [Attr(desugarer_blame(355), "val", word)], [])
}

fn space_node(blame: Blame) {
  V(blame, "__OneSpace", [], [])
}

fn newline_node(blame: Blame) {
  V(blame, "__OneNewLine", [], [])
}

fn end_node(blame: Blame) {
  V(blame, "__EndTokenizedT", [], [])
}

fn tokenize_string_acc(
  past_tokens: List(VXML),
  current_blame: Blame,
  leftover: String,
) -> List(VXML) {
  case string.split_once(leftover, " ") {
    Ok(#("", after)) -> tokenize_string_acc(
      [space_node(current_blame), ..past_tokens],
      bl.advance(current_blame, 1),
      after,
    )
    Ok(#(before, after)) -> tokenize_string_acc(
      [space_node(current_blame), word_node(current_blame, before), ..past_tokens],
      bl.advance(current_blame, string.length(before) + 1),
      after,
    )
    Error(Nil) -> case leftover == "" {
      True -> past_tokens |> list.reverse
      False -> [word_node(current_blame, leftover), ..past_tokens] |> list.reverse
    }
  }
}

fn tokenize_t(vxml: VXML) -> List(VXML) {
  let assert T(blame, lines) = vxml
  lines
  |> list.index_map(fn(line, i) {
    tokenize_string_acc(
      [],
      line.blame,
      line.content,
    )
    |> list.prepend(case i == 0 {
      True -> start_node(line.blame)
      False -> newline_node(line.blame)
    })
  })
  |> list.flatten
  |> list.append([end_node(blame)])
}

fn tokenize_if_t_or_has_href_tag_recursive(vxml: VXML) -> List(VXML) {
  case vxml {
    T(_, _) -> tokenize_t(vxml)
    V(_, _, _, children) -> case infra.v_has_attr_with_key(vxml, "href") {
      True -> {
        let children = list.flat_map(children, tokenize_if_t_or_has_href_tag_recursive)
        [V(..vxml, children: children)]
      }
      False -> [vxml]
    }
  }
}

fn tokenize_maybe(children: List(VXML)) -> Option(List(VXML)) {
  case list.any(children, infra.is_v_and_has_attr_with_key(_, "href")) {
    True -> {
      children
      |> list.map(tokenize_if_t_or_has_href_tag_recursive)
      |> list.flatten
      |> Some
    }
    False -> None
  }
}

// fn echo_pattern(
//   tokens: LinkPattern,
//   banner: String,
// ) -> Nil {
//   io.println("")
//   io.println(banner <> ":")
//   list.each(
//     tokens,
//     fn(t){io.println("  " <> ins(t))}
//   )
//   Nil
// }

fn nodemap(
  vxml: VXML,
  inner: InnerParam,
) -> VXML {
  case vxml {
    V(_, _, _, children) -> {
      use atomized <- on.none_some(
        tokenize_maybe(children),
        vxml,
      )

      let atomized =
        atomized
        |> match_until_end(inner.0, inner.1)
        |> detokenize_maybe([], [])

      V(..vxml, children: atomized)
    }
    _ -> vxml
  }
}

fn nodemap_factory(inner: InnerParam) -> n2t.OneToOneNoErrorNodeMap {
  nodemap(_, inner)
}

fn transform_factory(inner: InnerParam) -> DesugarerTransform {
  n2t.one_to_one_no_error_nodemap_2_desugarer_transform(nodemap_factory(inner))
}

type PatternTokenClassification {
  TextPatternToken
  NonTextPatternToken
  StartTToken
  EndTToken
}

type PatternTokenTransition {
  TextToNonText
  NonTextToText
  NoTransition
}

fn classify_pattern_token(token: PatternToken) -> PatternTokenClassification {
  case token {
    Space | Word(_) -> TextPatternToken
    ContentVar(_) | A(_, _, _, _) -> NonTextPatternToken
    StartT -> StartTToken
    EndT -> EndTToken
  }
}

fn first_token_classification(pattern: LinkPattern) -> PatternTokenClassification {
  let assert [first, ..] = pattern
  classify_pattern_token(first)
}

fn last_token_classification(pattern: LinkPattern) -> PatternTokenClassification {
  let assert Ok(last) = list.last(pattern)
  classify_pattern_token(last)
}

fn first_and_last_classifications(pattern: LinkPattern) -> #(PatternTokenClassification, PatternTokenClassification) {
  #(first_token_classification(pattern), last_token_classification(pattern))
}

fn check_pattern_token_text_non_text_consistency(
  tokens: LinkPattern,
)  -> LinkPattern {
  tokens
  |> list.fold(
    None,
    fn (acc, token) {
      // first check children of the token, while simulating "must start
      // in non-text mode, must end in non-text mode" for the children:
      let _ = case token {
        A(_, _, _, children) -> {
          check_pattern_token_text_non_text_consistency(list.append([EndT, ..children], [StartT]))
        }
        _ -> []
      }
      // ...now compare previous & this token transition:
      let next_classification = classify_pattern_token(token)
      case acc {
        None -> Some(next_classification)
        Some(prev_classification) -> {
          case prev_classification, next_classification {
            TextPatternToken, NonTextPatternToken -> panic as "text went straight to non-text"
            TextPatternToken, StartTToken -> panic as "text followed by start"
            NonTextPatternToken, TextPatternToken -> panic as "non-text went straight to text"
            NonTextPatternToken, EndTToken -> panic as "non-text followed by end"
            StartTToken, NonTextPatternToken -> panic as "start not followed by end or text"
            StartTToken, StartTToken -> panic as "start followed by start"
            EndTToken, TextPatternToken -> panic as "end not followed by start or non-text"
            EndTToken, EndTToken -> panic as "end followed by end"
            _, _ -> Some(next_classification)
          }
        }
      }
    }
  )
  tokens
}

fn transition_kind(from: PatternToken, to: PatternToken) -> PatternTokenTransition {
  case classify_pattern_token(from), classify_pattern_token(to) {
    TextPatternToken, NonTextPatternToken -> TextToNonText
    NonTextPatternToken, TextPatternToken -> NonTextToText
    TextPatternToken, TextPatternToken -> NoTransition
    NonTextPatternToken, NonTextPatternToken -> NoTransition
    _, _ -> panic as "not expecting StartT or EndT tokens in this function"
  }
}

fn insert_start_t_end_t_into_link_pattern(
  pattern_tokens: LinkPattern
) -> LinkPattern {
  list.fold(
    pattern_tokens,
    [],
    fn(acc, token) {
      let token = case token {
        A(_, _, _, children) -> {
          let children = insert_start_t_end_t_into_link_pattern(children)
          let children = case first_and_last_classifications(children) {
            #(TextPatternToken, TextPatternToken) -> list.append([StartT, ..children], [EndT])
            #(NonTextPatternToken, TextPatternToken) -> list.append(children, [EndT])
            #(TextPatternToken, NonTextPatternToken) -> [StartT, ..children]
            #(NonTextPatternToken, NonTextPatternToken) -> children
            #(_, _) -> panic as "not expecting StartT or EndT tokens in insert_start_t_end_t_into_link_pattern"
          }
          A(..token, children: children)
        }
        _ -> token
      }
      case acc {
        [] -> [token]
        [last, ..] -> case transition_kind(last, token) {
          TextToNonText -> [token, EndT, ..acc]
          NonTextToText -> [token, StartT, ..acc]
          NoTransition -> [token, ..acc]
        }
      }
    }
  )
  |> list.reverse
}

fn make_target_pattern_substitutable_for_source_pattern(
  source: LinkPattern,
  target: LinkPattern,
) -> LinkPattern {
  let #(source_first, source_last) = first_and_last_classifications(source)
  let #(target_first, target_last) = first_and_last_classifications(target)
  let target = case source_first, target_first {
    TextPatternToken, NonTextPatternToken -> [EndT, ..target]
    NonTextPatternToken, TextPatternToken -> [StartT, ..target]
    TextPatternToken, TextPatternToken -> target
    NonTextPatternToken, NonTextPatternToken -> target
    _, _ -> panic as "expecting Text/NonText tokens at start of source & target patterns"
  }
  let target = case source_last, target_last {
    TextPatternToken, NonTextPatternToken -> list.append(target, [StartT])
    NonTextPatternToken, TextPatternToken -> list.append(target, [EndT])
    TextPatternToken, TextPatternToken -> target
    NonTextPatternToken, NonTextPatternToken -> target
    _, _ -> panic as "expecting Text/NonText tokens at end of source & target patterns"
  }
  target
}

fn check_target_pattern_substitutable_for_source_pattern(
  source: LinkPattern,
  target: LinkPattern,
) -> Nil {
  check_pattern_token_text_non_text_consistency(source)
  check_pattern_token_text_non_text_consistency(target)
  let #(source_first, source_last) = first_and_last_classifications(source)
  let #(target_first, target_last) = first_and_last_classifications(target)
  case source_first {
    TextPatternToken -> { let assert True = target_first == TextPatternToken || target_first == EndTToken }
    NonTextPatternToken -> { let assert True = target_first == NonTextPatternToken || target_first == StartTToken }
    _ -> panic as "expecting Text/NonText token at start of source pattern"
  }
  case source_last {
    TextPatternToken -> { let assert True = target_last == TextPatternToken || target_last == StartTToken }
    NonTextPatternToken -> { let assert True = target_last == NonTextPatternToken || target_last == EndTToken }
    _ -> panic as "expecting Text/NonText token at end of source pattern"
  }
  Nil
}

fn pseudoword_to_pattern_tokens(word: String, re: regexp.Regexp) -> List(PatternToken) {
  // this is what it means to be a pseudoword:
  assert word == " " || {!string.contains(word, " ") && word != ""}

  // case 1: a space
  use <- on.lazy_true_false(word == " ", fn(){[Space]})

  // case 2: an ordinary word
  use <- on.lazy_false_true(regexp.check(re, word), fn(){[Word(word)]})

  // case 3: a word containing 'ContentVar' patterns
  regexp.split(re, word)
  |> list.index_map(
    // example of splits for _1_._2_ ==> ["", "_1_", ".", "_2_", ""]
    fn(x, i) {
      case i % 2 == 0 {
        True -> case x {
          "" -> None
          _ -> Some(Word(x))
        }
        False -> {
          let assert True = string.starts_with(x, "_") && string.ends_with(x, "_") && string.length(x) > 2
          let assert Ok(x) = x |> string.drop_end(1) |> string.drop_start(1) |> int.parse
          Some(ContentVar(x))
        }
      }
    }
  )
  |> option.values
}

fn text_to_link_pattern(content: String, re: regexp.Regexp) -> Result(LinkPattern, DesugaringError) {
  content
  |> string.split(" ")
  |> list.intersperse(" ")
  |> list.filter(fn(s){s != ""})
  |> list.flat_map(pseudoword_to_pattern_tokens(_, re))
  |> Ok
}

fn vxml_to_link_pattern(
  vxml: VXML,
  re: regexp.Regexp,
) -> Result(LinkPattern, DesugaringError) {
  case vxml {
    T(_, [Line(_, content)]) ->
      text_to_link_pattern(content, re)

    T(_, lines) ->
      Error(DesugaringError(bl.no_blame, "T-node in parsed link pattern contains more than " <> ins(list.length(lines)) <> " != 1 line"))

    V(_, tag, attrs, children) -> {
      use children <- on.ok(
        children
        |> list.map(vxml_to_link_pattern(_, re))
        |> result.all
        |> result.map(list.flatten)
      )

      use <- on.true_false(
        tag == "root",
        Ok(children),
      )

      assert tag == "a"

      use href_attr <- on.lazy_empty_gt1_singleton(
        infra.attrs_with_key(attrs, "href"),
        fn() { Error(DesugaringError(bl.no_blame, "<a>-tag missing 'href' attr")) },
        fn(_, _, _) { Error(DesugaringError(bl.no_blame, "<a>-tag with >1 'href' attr")) },
      )

      use href_value <- on.error_ok(
        int.parse(href_attr.val),
        fn(_) { Error(DesugaringError(bl.no_blame, "could not parse <a>-href attr as integer: " <> href_attr.val)) },
      )

      use classes <- on.ok(
        case infra.attrs_with_key(attrs, "class") {
          [] -> Ok("")
          [one] -> Ok(one.val)
          _ -> Error(DesugaringError(bl.no_blame, "more than one class attr inside <a> tag"))
        }
      )

      Ok([A(tag: tag, classes: classes, href: href_value, children: children)])
    }
  }
}

fn parse_link_pattern(
  s: String,
  re: regexp.Regexp,
) -> Result(LinkPattern, DesugaringError) {
  use root <- on.error_ok(
    vxml.streaming_based_xml_parser_string_version(s, "r4l"),
    fn(e) { Error(DesugaringError(bl.no_blame, "could not parse link pattern '" <> s <> "': " <> ins(e))) }
  )

  use pattern <- on.ok(vxml_to_link_pattern(root, re))

  pattern
  |> insert_start_t_end_t_into_link_pattern
  |> check_pattern_token_text_non_text_consistency
  |> Ok
}

fn make_sure_attrs_are_quoted(input: String, re: regexp.Regexp) -> String {
  regexp.match_map(re, input, fn(match: regexp.Match) {
    case match.submatches {
      [Some(key), Some(value)] -> key <> "=\"" <> value <> "\""
      _ -> match.content
    }
  })
}

fn string_pair_to_link_pattern_pair(string_pair: #(String, String)) -> Result(#(LinkPattern, LinkPattern), DesugaringError) {
  let #(s1, s2) = string_pair
  let assert Ok(re1) = regexp.compile("([a-zA-Z0-9-]+)=([^\"'][^ >]*)", regexp.Options(True, True))
  let assert Ok(re2) = regexp.from_string("(_[0-9]+_)")

  use pattern1 <- on.ok(
    { "<root>" <> s1 <> "</root>" }
    |> make_sure_attrs_are_quoted(re1)
    |> parse_link_pattern(re2)
  )

  use pattern2 <- on.ok(
    { "<root>" <> s2 <> "</root>" }
    |> make_sure_attrs_are_quoted(re1)
    |> parse_link_pattern(re2)
  )

  let pattern2 = make_target_pattern_substitutable_for_source_pattern(pattern1, pattern2)
  check_target_pattern_substitutable_for_source_pattern(pattern1, pattern2)

  Ok(#(pattern1, pattern2))
}

fn get_content_vars(
  pattern2: LinkPattern,
) -> List(Int) {
  list.map(pattern2, fn(token) {
    case token {
      ContentVar(var) -> [var]
      A(_, _, _, sub_pattern) -> get_content_vars(sub_pattern)
      _ -> []
    }
  })
  |> list.flatten
}

fn get_href_vars(
  pattern2: LinkPattern,
) -> List(Int) {
  list.map(pattern2, fn(token) {
    case token {
      A(_, _, var, _) -> [var]
      _ -> []
    }
  })
  |> list.flatten
}

fn check_each_content_var_is_sourced(pattern2: LinkPattern, source_vars: List(Int)) -> Result(Nil, Int) {
  let content_vars = get_content_vars(pattern2)
  case list.find(content_vars, fn(var){
    !{ list.contains(source_vars, var) }
  }) {
    Ok(var) -> Error(var)
    Error(_) -> Ok(Nil)
  }
}

fn check_each_href_var_is_sourced(pattern2: LinkPattern, href_vars: List(Int)) -> Result(Nil, Int) {
  let vars = get_href_vars(pattern2)
  case list.find(vars, fn(var){
    !{ list.contains(href_vars, var) }
  }) {
    Ok(var) -> Error(var)
    Error(_) -> Ok(Nil)
  }
}

fn collect_unique_content_vars(pattern1: LinkPattern) -> Result(List(Int), Int) {
  let vars = get_content_vars(pattern1)
  case infra.get_duplicate(vars) {
    None -> Ok(vars)
    Some(int) -> Error(int)
  }
}

fn collect_unique_href_vars(pattern1: LinkPattern) -> Result(List(Int), Int) {
  let vars = get_href_vars(pattern1)
  case infra.get_duplicate(vars) {
    None -> Ok(vars)
    Some(int) -> Error(int)
  }
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  use #(pattern1, pattern2) <- on.ok(string_pair_to_link_pattern_pair(param))

  use unique_href_vars <- on.ok(
    collect_unique_href_vars(pattern1)
    |> result.map_error(fn(var){ DesugaringError(desugarer_blame(846), "Source pattern " <> param.0 <>" has duplicate declaration of href variable: " <> ins(var) ) })
  )

  use unique_content_vars <- on.ok(
    collect_unique_content_vars(pattern1)
    |> result.map_error(fn(var){ DesugaringError(desugarer_blame(851), "Source pattern " <> param.0 <>" has duplicate declaration of content variable: " <> ins(var)) })
  )

  use _ <- on.ok(
    check_each_href_var_is_sourced(pattern2, unique_href_vars)
    |> result.map_error(fn(var){ DesugaringError(desugarer_blame(856), "Target pattern " <> param.1 <> " has a declaration of unsourced href variable: " <> ins(var)) })
  )

  use _ <- on.ok(
    check_each_content_var_is_sourced(pattern2, unique_content_vars)
    |> result.map_error(fn(var){ DesugaringError(desugarer_blame(861), "Target pattern " <> param.1 <> " has a declaration of unsourced content variable: " <> ins(var)) })
  )

  Ok(#(pattern1, pattern2))
}

type Param = #(String,   String)
//             ↖         ↖
//             source    target
//             pattern   pattern

type InnerParam = #(LinkPattern, LinkPattern)

pub const name = "rearrange_links"
fn desugarer_blame(line_no: Int) { bl.Des([], name, line_no) }

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// matches appearance of first String while
/// considering (x) as a variable and replaces it
/// with the second String (x) can be used in second
/// String to use the variable from first String
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
  []
}

pub fn assertive_tests() {
  infra.assertive_test_collection_from_data(name, assertive_tests_data(), constructor)
}
