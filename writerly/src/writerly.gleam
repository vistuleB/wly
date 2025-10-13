import blame.{type Blame, prepend_comment as pc} as bl
import io_lines.{type InputLine, InputLine, type OutputLine, OutputLine} as io_l
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/pair
import gleam/result
import gleam/regexp.{type Regexp}
import gleam/string.{inspect as ins}
import simplifile
import vxml.{type Attr, type Line, type VXML, Attr, Line, T, V}
import dirtree as dt
import splitter
import on

type Return(a, b) {
  Return(a)
  NotReturn(b)
}

fn on_not_return(
  r: Return(a, b),
  on_not_return f1: fn(b) -> a,
) -> a {
  case r {
    Return(a) -> a
    NotReturn(b) -> f1(b)
  }
}

const debug = False

// ************************************************************
// public types
// ************************************************************

pub type Writerly {
  BlankLine(
    blame: Blame,
  )
  Blurb(
    blame: Blame,
    lines: List(Line),
  )
  CodeBlock(
    blame: Blame,
    attrs: List(Attr),
    lines: List(Line),
  )
  Tag(
    blame: Blame,
    name: String,
    attrs: List(Attr),
    children: List(Writerly),
  )
}

pub type ParseError {
  TagEmpty(blame: Blame)
  BadTag(blame: Blame, bad_name: String)
  BadKey(blame: Blame, bad_key: String)
  DuplicateIdInCodeBlockLanguageAnnotation(blame: Blame)
  IndentationTooLarge(blame: Blame, line: String)
  IndentationNotMultipleOfFour(blame: Blame, line: String)
  CodeBlockNotClosed(blame: Blame)
  CodeBlockUnwantedAnnotationAtClose(blame: Blame, opening_blame: Blame)
}

pub type AssemblyError {
  ReadFileError(String)
  ReadFileOrDirectoryError(String)
  TwoFilesSameName(String) // because we accept both .emu and .wly extensions, but we want to avoid mixing error
}

pub type AssemblyOrParseError {
  ParseError(ParseError)
  AssemblyError(AssemblyError)
}

// ***************
// * local types *
// ***************

type FileHead =
  List(InputLine)

type BadTentativeTag {
  Empty
  BadTentativeTag(String)
}

type TentativeTagName =
  Result(String, BadTentativeTag)

type BadTentativeKey {
  BadTentativeKey(String)
  DuplicateId
}

type TentativeAttrKey =
  Result(String, BadTentativeKey)

type TentativeAttr {
  TentativeAttr(
    blame: Blame,
    key: TentativeAttrKey,
    val: String,
  )
}

type ClosingBackTicksError {
  UndesiredAnnotation(Blame, FileHead)
  NoBackticksFound(FileHead)
}

type NonemptySuffixDiagnostic {
  Pipe(annotation: String)
  TripleBacktick(annotation: String)
  Other(content: String)
}

type TentativeWriterly {
  TentativeBlankLine(blame: Blame)
  TentativeBlurb(blame: Blame, contents: List(Line))
  TentativeCodeBlock(
    blame: Blame,
    attrs: List(TentativeAttr),
    contents: List(Line),
  )
  TentativeTag(
    blame: Blame,
    tag: TentativeTagName,
    attrs: List(TentativeAttr),
    children: List(TentativeWriterly),
  )
  TentativeErrorIndentationTooLarge(blame: Blame, message: String)
  TentativeErrorIndentationNotMultipleOfFour(blame: Blame, message: String)
  TentativeErrorCodeBlockUnwantedAnnotationAtClose(blame: Blame, opening_blame: Blame, message: String)
  TentativeErrorCodeBlockNotClosed(blame: Blame)
}

// ************
// * FileHead *
// ************

fn current_line(head: FileHead) -> Option(InputLine) {
  case head {
    [] -> None
    [first, ..] -> Some(first)
  }
}

fn move_forward(head: FileHead) -> FileHead {
  let assert [_, ..rest] = head
  rest
}

// ************************
// * parse_from_tentative *
// ************************

fn tentative_attr_to_attr(
  t: TentativeAttr,
) -> Result(Attr, ParseError) {
  case t.key {
    Ok(key) -> Ok(Attr(blame: t.blame, key: key, val: t.val))
    Error(BadTentativeKey(key)) -> Error(BadKey(t.blame, key))
    Error(DuplicateId) -> Error(DuplicateIdInCodeBlockLanguageAnnotation(t.blame))
  }
}

fn tentative_attrs_to_attrs(
  attrs: List(TentativeAttr),
) -> Result(List(Attr), ParseError) {
  case attrs {
    [] -> Ok([])
    [first, ..rest] ->
      case tentative_attr_to_attr(first) {
        Error(error) -> Error(error)
        Ok(attr) ->
          case tentative_attrs_to_attrs(rest) {
            Ok(attrs) ->
              Ok(list.prepend(attrs, attr))

            Error(error) -> Error(error)
          }
      }
  }
}

fn tentatives_to_writerlys(
  tentatives: List(TentativeWriterly),
) -> Result(List(Writerly), ParseError) {
  case tentatives {
    [] -> Ok([])
    [first, ..rest] ->
      case parse_from_tentative(first) {
        Ok(parsed) ->
          case tentatives_to_writerlys(rest) {
            Ok(parseds) -> Ok(list.prepend(parseds, parsed))

            Error(error) -> Error(error)
          }

        Error(error) -> Error(error)
      }
  }
}

fn parse_from_tentative(
  tentative: TentativeWriterly,
) -> Result(Writerly, ParseError) {
  case tentative {
    TentativeErrorCodeBlockUnwantedAnnotationAtClose(blame, opening_blame, _) ->
      Error(CodeBlockUnwantedAnnotationAtClose(blame, opening_blame))

    TentativeErrorIndentationTooLarge(blame, message) ->
      Error(IndentationTooLarge(blame, message))

    TentativeErrorIndentationNotMultipleOfFour(blame, message) ->
      Error(IndentationNotMultipleOfFour(blame, message))

    TentativeErrorCodeBlockNotClosed(blame) -> Error(CodeBlockNotClosed(blame))

    TentativeBlankLine(blame) -> Ok(BlankLine(blame))

    TentativeBlurb(blame, contents) -> Ok(Blurb(blame, contents))

    TentativeCodeBlock(blame, attrs, contents) ->
      case tentative_attrs_to_attrs(attrs) {
        Ok(attrs) -> Ok(CodeBlock(blame, attrs, contents))
        Error(e) -> Error(e)
      }

    TentativeTag(
      blame,
      tentative_name,
      tentative_attrs,
      tentative_children,
    ) ->
      case tentative_name {
        Error(Empty) -> Error(TagEmpty(blame))

        Error(BadTentativeTag(tag)) ->
          Error(BadTag(tentative.blame, tag))

        Ok(name) ->
          case tentative_attrs_to_attrs(tentative_attrs)
          {
            Error(error) -> Error(error)

            Ok(attrs) ->
              case tentatives_to_writerlys(tentative_children) {
                Error(error) -> Error(error)

                Ok(children) ->
                  Ok(Tag(
                    blame: tentative.blame,
                    name: name,
                    attrs: attrs,
                    children: children,
                  ))
              }
          }
      }
  }
}

fn nonempty_suffix_diagnostic(suffix: String) -> NonemptySuffixDiagnostic {
  let assert False = suffix == ""

  case suffix {
    "```" <> _ -> TripleBacktick(string.drop_start(suffix, 3))
    "|>" <> _ -> Pipe(string.drop_start(suffix, 2))
    _ -> Other(suffix)
  }
}

fn fast_forward_past_lines_of_indent_at_least(
  indent: Int,
  head: FileHead,
) -> FileHead {
  case current_line(head) {
    None -> head

    Some(InputLine(_, suffix_indent, _)) ->
      case suffix_indent < indent {
        True -> head

        False ->
          fast_forward_past_lines_of_indent_at_least(indent, move_forward(head))
      }
  }
}

fn tentative_attr(
  blame: Blame,
  pair: #(String, String),
  key_re: Regexp,
) -> TentativeAttr {
  let #(key, val) = pair
  assert !string.contains(key, "=")
  assert !string.is_empty(key)

  case regexp.check(key_re, key) {
    True -> TentativeAttr(blame: blame, key: Ok(key), val: val)

    False ->
      TentativeAttr(
        blame: blame,
        key: Error(BadTentativeKey(key)),
        val: val,
      )
  }
}

fn fast_forward_past_attr_lines_at_indent(
  indent: Int,
  head: FileHead,
  key_re: Regexp,
) -> #(List(TentativeAttr), FileHead) {
  case current_line(head) {
    None -> #([], head)

    Some(InputLine(blame, suffix_indent, suffix)) -> {
      case suffix == "" 
        || suffix_indent != indent
        || string.starts_with(suffix, "|>")
        || string.starts_with(suffix, "```")
      {
        True -> #([], head)

        False -> {
          case string.split_once(suffix, "=") {
            Error(_) -> #([], head)

            Ok(#(key, val)) -> {
              case string.contains(key, " ") || key == "" || string.starts_with(val, " ") {
                True -> #([], head)

                False -> {
                  let val = string.trim(val)

                  let attr_pair =
                    #(key, val)
                    |> tentative_attr(blame, _, key_re)

                  let #(more_attr_pairs, head_after_attrs) =
                    fast_forward_past_attr_lines_at_indent(
                      indent,
                      move_forward(head),
                      key_re,
                    )

                  #(
                    [attr_pair, ..more_attr_pairs],
                    head_after_attrs,
                  )
                }
              }
            }
          }
        }
      }
    }
  }
}

fn fast_forward_past_other_lines_at_indent(
  indent: Int,
  head: FileHead,
) -> #(List(Line), FileHead) {
  case current_line(head) {
    None -> #([], head)

    Some(InputLine(blame, suffix_indent, suffix)) -> {
      case suffix == "" {
        True -> #([], head)

        False -> {
          case suffix_indent != indent
            || string.starts_with(suffix, "|>")
            || string.starts_with(suffix, "```")
          {
            True -> #([], head)

            False -> {
              let line = Line(blame, suffix)

              let #(more_lines, head_after_others) =
                fast_forward_past_other_lines_at_indent(
                  indent,
                  move_forward(head),
                )

              #(
                list.prepend(more_lines, line),
                head_after_others,
              )
            }
          }
        }
      }
    }
  }
}

fn fast_forward_to_closing_backticks(
  indent: Int,
  head: FileHead,
) -> Result(#(List(Line), FileHead), ClosingBackTicksError) {
  case current_line(head) {
    None -> Error(NoBackticksFound(head))

    Some(InputLine(blame, suffix_indent, suffix)) -> {
      case suffix == "" {
        True ->
          case fast_forward_to_closing_backticks(indent, move_forward(head)) {
            Ok(#(lines, head_after_closing_backticks)) -> {
              let line =
                Line(
                  blame,
                  string.repeat(" ", int.max(0, suffix_indent - indent)),
                )

              Ok(#(
                list.prepend(lines, line),
                head_after_closing_backticks,
              ))
            }

            error -> error
          }

        False -> {
          case suffix_indent < indent {
            True -> Error(NoBackticksFound(head))

            False -> {
              let padded_suffix_length =
                suffix_indent + string.length(suffix) - indent
              let assert True = padded_suffix_length >= string.length(suffix)
              let padded_suffix =
                string.pad_start(suffix, to: padded_suffix_length, with: " ")
              let line = Line(blame, padded_suffix)

              case
                suffix_indent > indent || !string.starts_with(suffix, "```")
              {
                True ->
                  case
                    fast_forward_to_closing_backticks(
                      indent,
                      move_forward(head),
                    )
                  {
                    Ok(#(lines, head_after_closing_backticks)) ->
                      Ok(#(
                        list.prepend(lines, line),
                        head_after_closing_backticks,
                      ))

                    error -> error
                  }

                False -> {
                  let assert True = string.starts_with(suffix, "```")
                  let assert True = suffix_indent == indent
                  let annotation = string.drop_start(suffix, 3) |> string.trim

                  case string.is_empty(annotation) {
                    True -> Ok(#([], move_forward(head)))

                    False ->
                      Error(UndesiredAnnotation(blame, move_forward(head)))
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}

fn check_good_tag_name(proposed_name, tag_re) -> TentativeTagName {
  case string.is_empty(proposed_name) {
    True -> Error(Empty)
    False -> case regexp.check(tag_re, proposed_name) {
      True -> Ok(proposed_name)
      False -> Error(BadTentativeTag(proposed_name))
    }
  }
}

fn tentative_first_non_blank_line_is_blurb(
  nodes: List(TentativeWriterly),
) -> Bool {
  case nodes {
    [TentativeBlankLine(_), ..rest] ->
      tentative_first_non_blank_line_is_blurb(rest)
    [TentativeBlurb(_, _), ..] -> True
    _ -> False
  }
}

fn remove_starting_escapes(contents: List(Line)) -> List(Line) {
  let assert Ok(re) = regexp.from_string("^\\\\+\\s")
  list.map(contents, fn(line) {
    let new_content = case regexp.check(re, line.content) {
      False -> line.content
      True -> line.content |> string.drop_start(1)
    }
    Line(line.blame, new_content)
  })
}

fn expand_selector_split_while(
  s: splitter.Splitter,
  suffix: String,
  blame: Blame,
) -> #(String, List(#(Blame, String, String))) {
  let #(before, sep, after) = splitter.split(s, suffix)
  use _ <- on_not_return(case sep {
    "" -> Return(#(before, []))
    _ -> NotReturn(Nil)
  })
  let b1 = bl.advance(blame, string.length(before))
  let b2 = bl.advance(b1, string.length(sep))
  let #(u, others) = expand_selector_split_while(s, after, b2)
  #(before, [#(b1, sep, u), ..others])
}

type CSSSelectorPiece {
  Dot(blame: Blame, payload: String)
  Pound(blame: Blame, payload: String)
  Ampersand(blame: Blame, key: String, val: String)
}

fn css_selector_pieces(
  s: splitter.Splitter,
  shorthand: String,
  blame: Blame,
) -> #(String, List(CSSSelectorPiece)) {
  let #(tag, pieces) = expand_selector_split_while(s, shorthand, blame)
  let pieces = list.map(pieces, fn(p) {
    case p {
      #(b, ".", payload) -> Dot(b, payload)
      #(b, "#", payload) -> Pound(b, payload)
      #(b, "&", payload) -> case string.split_once(payload, "=") {
        Ok(#(key, val)) -> Ampersand(b, key, val)
        _ -> Ampersand(b, payload, "")
      }
      _ -> panic as "huh-huh"
    }
  })
  #(tag, pieces)
}

fn code_block_annotation_to_attrs_v2(
  blame: Blame,
  annotation: String,
  key_re: Regexp,
) -> List(TentativeAttr) {
  let annotation = string.trim_end(annotation)
  use _ <- on_not_return(case annotation {
    "" -> Return([])
    _ -> NotReturn(Nil)
  })
  let s = splitter.new([".", "#", "&"])
  let #(language, pieces) = css_selector_pieces(s, annotation, blame)
  let #(dots, pounds, ampersands) = list.fold(
    pieces,
    #([], [], []),
    fn(acc, p) {
      case p {
        Dot(..) -> #([p, ..acc.0], acc.1, acc.2)
        Pound(..) -> #(acc.0, [p, ..acc.1], acc.2)
        Ampersand(..) -> #(acc.0, acc.1, [p, ..acc.2])
      }
    }
  )
  let language_attr = case language {
    "" -> None
    _ -> Some(TentativeAttr(blame, Ok("language"), language))
  }
  let class_attr = case dots {
    [] -> None
    [first, ..] -> {
      let val = list.map(dots, fn(d) {
        let assert Dot(..) = d
        d.payload
      }) |> list.reverse |> string.join(" ")
      Some(TentativeAttr(first.blame, Ok("class"), val))
    }
  }
  let id_attrs = case pounds {
    [] -> []
    [one] -> {
      let assert Pound(..) = one
      [TentativeAttr(one.blame, Ok("id"), one.payload)]
    }
    _ -> list.map(pounds, fn(one) {
      let assert Pound(..) = one
      TentativeAttr(one.blame, Error(DuplicateId), one.payload)
    })
  }
  let other_attrs = list.map(ampersands, fn(a) {
    let assert Ampersand(blame, key, val) = a
    case regexp.check(key_re, key) {
      True -> TentativeAttr(blame, Ok(key), val)
      False -> TentativeAttr(blame, Error(BadTentativeKey(key)), val)
    }
  })
  list.flatten([
    [language_attr, class_attr] |> option.values,
    id_attrs |> list.reverse,
    other_attrs |> list.reverse,
  ])  
}

fn tentative_parse_at_indent(
  indent: Int,
  head: FileHead,
  tag_re: Regexp,
  key_re: Regexp,
) -> #(List(TentativeWriterly), List(TentativeWriterly), FileHead) {
  case current_line(head) {
    None -> #([], [], head)

    Some(InputLine(blame, suffix_indent, suffix)) -> {
      case suffix == "" {
        True -> {
          let tentative_blank_line = TentativeBlankLine(blame)
          let #(siblings, siblings_trailing_blank_lines, remainder_after_indent) =
            tentative_parse_at_indent(indent, move_forward(head), tag_re, key_re)

          case siblings {
            [] -> #(
              siblings,
              list.prepend(siblings_trailing_blank_lines, tentative_blank_line),
              remainder_after_indent,
            )
            _ -> #(
              list.prepend(siblings, tentative_blank_line),
              siblings_trailing_blank_lines,
              remainder_after_indent,
            )
          }
        }

        False -> {
          case suffix_indent < indent {
            True -> {
              case suffix_indent > indent - 4 {
                True -> {
                  let error_message =
                    ins(suffix_indent) <> " spaces before " <> ins(suffix)

                  let error =
                    TentativeErrorIndentationNotMultipleOfFour(
                      blame,
                      error_message,
                    )

                  let #(
                    siblings,
                    siblings_trailing_blank_lines,
                    head_after_indent,
                  ) = tentative_parse_at_indent(indent, move_forward(head), tag_re, key_re)

                  #(
                    list.prepend(siblings, error),
                    siblings_trailing_blank_lines,
                    head_after_indent,
                  )
                }

                False -> #([], [], head)
              }
            }

            False -> {
              case suffix_indent > indent {
                True -> {
                  let head_after_oversize_indent =
                    fast_forward_past_lines_of_indent_at_least(
                      suffix_indent,
                      head,
                    )

                  let #(
                    siblings,
                    siblings_trailing_blank_lines,
                    head_after_indent,
                  ) =
                    tentative_parse_at_indent(
                      indent,
                      head_after_oversize_indent,
                      tag_re,
                      key_re,
                    )

                  case suffix_indent % 4 == 0 {
                    True -> {
                      let error_message =
                        string.repeat(" ", suffix_indent) <> suffix

                      let error =
                        TentativeErrorIndentationTooLarge(blame, error_message)

                      #(
                        list.prepend(siblings, error),
                        siblings_trailing_blank_lines,
                        head_after_indent,
                      )
                    }

                    False -> {
                      let error_message =
                        ins(suffix_indent) <> " spaces before " <> ins(suffix)

                      let error =
                        TentativeErrorIndentationNotMultipleOfFour(
                          blame,
                          error_message,
                        )

                      #(
                        list.prepend(siblings, error),
                        siblings_trailing_blank_lines,
                        head_after_indent,
                      )
                    }
                  }
                }

                False -> {
                  let assert True = suffix_indent == indent

                  case nonempty_suffix_diagnostic(suffix) {
                    Pipe(tag) -> {
                      let #(tentative_attrs, head_after_attrs) =
                        fast_forward_past_attr_lines_at_indent(
                          indent + 4,
                          move_forward(head),
                          key_re,
                        )

                      let #(
                        children,
                        children_trailing_blank_lines,
                        head_after_children,
                      ) =
                        tentative_parse_at_indent(
                          indent + 4,
                          head_after_attrs,
                          tag_re,
                          key_re,
                        )

                      // filter out syntax-imposed blank line:
                      let children = case children {
                        [TentativeBlankLine(_), ..rest] -> {
                          case tentative_first_non_blank_line_is_blurb(rest) {
                            True -> rest
                            False -> children
                          }
                        }
                        _ -> children
                      }

                      let tentative_tag =
                        TentativeTag(
                          blame: blame,
                          tag: check_good_tag_name(string.trim(tag), tag_re),
                          attrs: tentative_attrs,
                          children: children,
                        )

                      let #(
                        siblings,
                        siblings_trailing_blank_lines,
                        head_after_indent,
                      ) = tentative_parse_at_indent(indent, head_after_children, tag_re, key_re)

                      case siblings {
                        [] -> #(
                          [tentative_tag],
                          list.append(
                            children_trailing_blank_lines,
                            siblings_trailing_blank_lines,
                          ),
                          head_after_indent,
                        )
                        _ -> #(
                          list.prepend(
                            list.append(children_trailing_blank_lines, siblings),
                            tentative_tag,
                          ),
                          siblings_trailing_blank_lines,
                          head_after_indent,
                        )
                      }
                    }

                    TripleBacktick(annotation) ->
                      case
                        fast_forward_to_closing_backticks(
                          indent,
                          move_forward(head),
                        )
                      {
                        Ok(#(contents, head_after_code_block)) -> {
                          let tentative_code_block =
                            TentativeCodeBlock(
                              blame: blame,
                              attrs: code_block_annotation_to_attrs_v2(blame, annotation, key_re),
                              contents: contents,
                            )

                          let #(
                            siblings,
                            siblings_trailing_blank_lines,
                            head_after_indent,
                          ) =
                            tentative_parse_at_indent(
                              indent,
                              head_after_code_block,
                              tag_re,
                              key_re,
                            )

                          #(
                            list.prepend(siblings, tentative_code_block),
                            siblings_trailing_blank_lines,
                            head_after_indent,
                          )
                        }

                        Error(UndesiredAnnotation(
                          closing_blame,
                          head_after_error,
                        )) -> {
                          let error_message =
                            "closing backticks at"
                            <> bl.blame_digest(closing_blame)
                            <> " for backticks opened at "
                            <> bl.blame_digest(blame)
                            <> " carry unexpected annotation"

                          let tentative_error =
                            TentativeErrorCodeBlockUnwantedAnnotationAtClose(
                              closing_blame,
                              blame,
                              error_message,
                            )

                          let #(
                            siblings,
                            siblings_trailing_blank_lines,
                            head_after_indent,
                          ) =
                            tentative_parse_at_indent(indent, head_after_error, tag_re, key_re)

                          #(
                            list.prepend(siblings, tentative_error),
                            siblings_trailing_blank_lines,
                            head_after_indent,
                          )
                        }

                        Error(NoBackticksFound(head_after_indent)) -> {
                          let tentative_error =
                            TentativeErrorCodeBlockNotClosed(blame)

                          #([tentative_error], [], head_after_indent)
                        }
                      }

                    Other(_) -> {
                      let line = Line(blame, suffix)

                      let #(more_lines, head_after_others) =
                        fast_forward_past_other_lines_at_indent(
                          indent,
                          move_forward(head),
                        )

                      let tentative_blurb =
                        TentativeBlurb(
                          blame: blame,
                          contents: list.prepend(
                            more_lines,
                            line,
                          ) |> remove_starting_escapes,
                        )

                      let #(
                        siblings,
                        siblings_trailing_blank_lines,
                        head_after_indent,
                      ) = tentative_parse_at_indent(indent, head_after_others, tag_re, key_re)

                      #(
                        list.prepend(siblings, tentative_blurb),
                        siblings_trailing_blank_lines,
                        head_after_indent,
                      )
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}

//****************************************
//* tentative parsing api (input lines) *
//****************************************

fn tentative_parse_input_lines(
  head: FileHead,
) -> List(TentativeWriterly) {
  let assert Ok(tag_re) = regexp.from_string("^[a-zA-Z_\\:][-a-zA-Z0-9\\._\\:]*$")
  let assert Ok(key_re) = regexp.from_string("^[a-zA-Z_][-a-zA-Z0-9\\._\\:]*$")
  let head = list.filter(head, fn(line) { !string.starts_with(line.suffix, "!!") })
  let #(parsed, _, final_head) = tentative_parse_at_indent(0, head, tag_re, key_re)
  assert final_head == []

  let parsed =
    list.drop_while(parsed, fn(writerly) {
      case writerly {
        TentativeBlankLine(..) -> True
        _ -> False
      }
    })

  case debug {
    True -> {
      io.println("\n\n(tentative parse:)")
      tentatives_table(parsed, "tentative_parse_input_lines", 0)
      io.println("(tentative end)\n\n")
    }
    False -> Nil
  }

  parsed
}

//***************************************
//* writerly parsing api (input lines) *
//***************************************

pub fn parse_input_lines(
  lines: List(InputLine),
) -> Result(List(Writerly), ParseError) {
  lines
  |> tentative_parse_input_lines
  |> tentatives_to_writerlys
}

//*********************************
//* writerly parsing api (string) *
//*********************************

pub fn parse_string(
  source: String,
  filename: String,
) -> Result(List(Writerly), ParseError) {
  source
  |> io_l.string_to_input_lines(filename, 0)
  |> parse_input_lines
}

//**********************
//* printing Tentative *
//**********************

fn tentative_error_blame_and_type_and_message(
  t: TentativeWriterly,
) -> #(Blame, String, String) {
  case t {
    TentativeBlankLine(_) -> panic as "not an error node"
    TentativeBlurb(_, _) -> panic as "not an error node"
    TentativeCodeBlock(_, _, _) -> panic as "not an error node"
    TentativeTag(_, _, _, _) -> panic as "not an error node"
    TentativeErrorIndentationTooLarge(blame, message) -> #(
      blame,
      "IndentationTooLarge",
      message,
    )
    TentativeErrorIndentationNotMultipleOfFour(blame, message) -> #(
      blame,
      "IndentationNotMultipleOfFour",
      message,
    )
    TentativeErrorCodeBlockNotClosed(blame) -> #(
      blame,
      "CodeBlockNotClosed",
      "",
    )
    TentativeErrorCodeBlockUnwantedAnnotationAtClose(blame, _opening_blame, message) -> #(
      blame,
      "CodeBlockUnwantedAnnotationAtClose",
      message,
    )
  }
}

fn line_to_output_line(
  line: Line,
  indentation: Int,
) -> OutputLine {
  OutputLine(line.blame, indentation, line.content)
}

fn lines_to_output_lines(
  lines: List(Line),
  indentation: Int,
) -> List(OutputLine) {
  lines
  |> list.map(line_to_output_line(_, indentation))
}

fn tentative_attr_to_output_line(
  attr: TentativeAttr,
  indentation: Int,
) -> OutputLine {
  case attr.key {
    Ok(_) ->
      OutputLine(
        attr.blame,
        indentation,
        ins(attr.key) <> "=" <> attr.val,
      )
    Error(BadTentativeKey(bad_key)) ->
      OutputLine(
        attr.blame
          |> pc("ERROR bad xml key"),
        indentation,
        bad_key <> "=" <> attr.val,
      )
    Error(DuplicateId) ->
      OutputLine(
        attr.blame
          |> pc("ERROR duplicate 'id'"),
        indentation,
        "id=" <> attr.val,
      )
  }
}

fn tentative_attrs_to_output_lines(
  attrs: List(TentativeAttr),
  indentation: Int,
) -> List(OutputLine) {
  attrs
  |> list.map(tentative_attr_to_output_line(_, indentation))
}

fn tentative_attrs_to_code_block_annotation(
  attrs: List(TentativeAttr),
) -> String {
  list.index_map(
    attrs,
    fn (attr, i) {
      let key = case attr.key {
        Error(BadTentativeKey(key)) -> "BadTentativeKey(" <> key <> ")"
        Error(DuplicateId) -> "DuplicateId"
        Ok(key) -> key
      }
      case i == 0 && key == "language" {
        True -> attr.val
        False -> key <> "=" <> attr.val
      }
    }
  )
  |> string.join("&")
}

fn attrs_to_code_block_annotation(
  attrs: List(Attr),
) -> String {
  list.index_map(
    attrs,
    fn (attr, i) {
      case i == 0 && attr.key == "language" {
        True -> attr.val
        False -> attr.key <> "=" <> attr.val
      }
    }
  )
  |> string.join("&")
}

fn tentative_to_output_lines_internal(
  t: TentativeWriterly,
  indentation: Int,
) -> List(OutputLine) {
  case t {
    TentativeBlankLine(blame) -> {
      [OutputLine(blame, 0, "")]
    }
    TentativeBlurb(_, lines) ->
      lines_to_output_lines(lines, indentation)
    TentativeCodeBlock(blame, attrs, lines) -> {
      let annotation = tentative_attrs_to_code_block_annotation(attrs)
      list.flatten([
        [OutputLine(blame, indentation, "```" <> annotation)],
        lines_to_output_lines(lines, indentation),
        [OutputLine(blame, indentation, "```")],
      ])
    }
    TentativeTag(blame, maybe_tag, attrs, children) -> {
      let tag_line = case maybe_tag {
        Ok(tag) -> OutputLine(blame, indentation, "|> " <> tag)
        Error(Empty) ->
          OutputLine(
            blame |> bl.prepend_comment("ERROR empty tag"),
            indentation,
            "<>",
          )
        Error(BadTentativeTag(bad_tag)) ->
          OutputLine(
            blame |> bl.prepend_comment("ERROR bad xml tag"),
            indentation,
            "|> " <> bad_tag,
          )
      }
      let attr_lines =
        tentative_attrs_to_output_lines(attrs, indentation + 4)
      let children_lines =
        tentatives_to_output_lines_internal(children, indentation + 4)
      let blank_lines = case list.is_empty(children_lines) {
        True -> []
        False -> [OutputLine(blame, 0, "")]
      }
      list.flatten([[tag_line], attr_lines, blank_lines, children_lines])
    }
    _ -> {
      let #(blame, error_type, message) =
        tentative_error_blame_and_type_and_message(t)
      [
        OutputLine(
          blame
            |> bl.prepend_comment("ERROR " <> error_type),
          indentation,
          message,
        ),
      ]
    }
  }
}

fn tentatives_to_output_lines_internal(
  tentatives: List(TentativeWriterly),
  indentation: Int,
) -> List(OutputLine) {
  tentatives
  |> list.map(tentative_to_output_lines_internal(_, indentation))
  |> list.flatten
}

fn tentatives_table(
  tentatives: List(TentativeWriterly),
  banner: String,
  indent: Int,
) -> String {
  tentatives
  |> tentatives_to_output_lines_internal(0)
  |> io_l.output_lines_table(banner, indent)
}

//*************************************
//* Writerly -> blamed lines internals
//*************************************

pub fn writerly_annotate_blames(writerly: Writerly) -> Writerly {
  case writerly {
    BlankLine(blame) -> BlankLine(blame |> pc("BlankLine"))
    Blurb(blame, lines) ->
      Blurb(
        blame |> pc("Blurb"),
        list.index_map(lines, fn(line, i) {
          Line(
            line.blame
              |> pc("Blurb > Line(" <> ins(i + 1) <> ")"),
            line.content,
          )
        }),
      )
    CodeBlock(blame, attrs, lines) -> {
      let annotation = attrs_to_code_block_annotation(attrs)
      CodeBlock(
        blame |> pc("CodeBlock:" <> annotation),
        attrs,
        list.index_map(lines, fn(line, i) {
          Line(
            line.blame
              |> pc("CodeBlock > Line(" <> ins(i + 1) <> ")"),
            line.content,
          )
        }),
      )
    }
    Tag(blame, tag, attrs, children) ->
      Tag(
        blame |> pc("Tag"),
        tag,
        list.index_map(attrs, fn(attr, i) {
          Attr(
            attr.blame |> pc("Tag > Attr(" <> ins(i + 1) <> ")"),
            attr.key,
            attr.val,
          )
        }),
        children
          |> list.map(writerly_annotate_blames),
      )
  }
}

fn attr_to_output_line(
  attr: Attr,
  indentation: Int,
) -> OutputLine {
  OutputLine(
    attr.blame,
    indentation,
    attr.key <> "=" <> attr.val,
  )
}

fn attrs_to_output_lines(
  attrs: List(Attr),
  indentation: Int,
) -> List(OutputLine) {
  attrs |> list.map(attr_to_output_line(_, indentation))
}

fn first_child_is_blurb_and_first_line_of_blurb_could_be_read_as_attr_value_pair(nodes: List(Writerly)) -> Bool {
  case nodes {
    [Blurb(_, lines), ..] -> {
      let assert [first, ..] = lines
      case string.split_once(first.content, "=") {
        Error(_) -> False
        Ok(#(before, _)) -> {
          let before = string.trim(before)
          !string.contains(before, " ") && before != ""
        }
      }
    }
    _ -> False
  }
}

fn writerly_to_output_lines_internal(
  t: Writerly,
  indentation: Int,
  annotate_blames: Bool,
) -> List(OutputLine) {
  case t {
    BlankLine(blame) -> [OutputLine(blame, 0, "")]
    Blurb(_, lines) ->
      lines_to_output_lines(lines, indentation)
    CodeBlock(blame, attrs, lines) -> {
      list.flatten([
        [OutputLine(blame, indentation, "```" <> attrs_to_code_block_annotation(attrs))],
        lines_to_output_lines(lines, indentation),
        [
          OutputLine(
            case annotate_blames {
              False -> blame
              True -> blame |> pc("CodeBlock end")
            },
            indentation,
            "```",
          ),
        ],
      ])
    }
    Tag(blame, tag, attrs, children) -> {
      let tag_line = OutputLine(blame, indentation, "|> " <> tag)
      let attr_lines =
        attrs_to_output_lines(attrs, indentation + 4)
      let children_lines =
        children
        |> list.map(writerly_to_output_lines_internal(_, indentation + 4, annotate_blames))
        |> list.flatten
      let buffer_lines = case first_child_is_blurb_and_first_line_of_blurb_could_be_read_as_attr_value_pair(children) {
        True -> {
          let blame = case annotate_blames {
            False -> blame |> bl.clear_comments
            True -> blame |> bl.clear_comments |> pc("(a-b separation line)")
          }
          [OutputLine(blame, 0, "")]
        }
        False -> []
      }
      list.flatten([[tag_line], attr_lines, buffer_lines, children_lines])
    }
  }
}

//*********************************
//* Writerly -> output lines api
//*********************************

pub fn writerly_to_output_lines(
  writerly: Writerly,
) -> List(OutputLine) {
  writerly
  |> writerly_to_output_lines_internal(0, False)
}

pub fn writerlys_to_output_lines(
  writerlys: List(Writerly),
) -> List(OutputLine) {
  writerlys
  |> list.map(writerly_to_output_lines)
  |> list.flatten
}

//*********************************
//* Writerly -> String api
//*********************************

pub fn writerly_to_string(writerly: Writerly) -> String {
  writerly
  |> writerly_to_output_lines()
  |> io_l.output_lines_to_string
}

pub fn writerlys_to_string(
  writerlys: List(Writerly),
) -> String {
  writerlys
  |> writerlys_to_output_lines()
  |> io_l.output_lines_to_string
}


//*********************************
//* echo_writerly api
//*********************************

pub fn writerly_table(writerly: Writerly, banner: String, indent: Int) -> String {
  writerly
  |> writerly_annotate_blames
  |> writerly_to_output_lines_internal(0, True)
  |> io_l.output_lines_table(banner, indent)
}

//*******************************
//* Writerly -> VXML
//*******************************

const writerly_blank_line_vxml_tag = "WriterlyBlankLine"
const writerly_code_block_vxml_tag = "WriterlyCodeBlock"

pub fn writerly_to_vxml(t: Writerly) -> VXML {
  case t {
    BlankLine(blame) ->
      V(
        blame: blame,
        tag: writerly_blank_line_vxml_tag,
        attrs: [],
        children: [],
      )

    Blurb(blame, lines) -> T(blame: blame, lines: lines)

    CodeBlock(blame, attrs, lines) ->
      V(
        blame: blame,
        tag: writerly_code_block_vxml_tag,
        attrs: attrs,
        children: [T(blame: blame, lines: lines)],
      )

    Tag(blame, tag, attrs, children) -> {
      V(
        blame: blame,
        tag: tag,
        attrs: attrs,
        children: children |> list.map(writerly_to_vxml),
      )
    }
  }
}

pub fn writerlys_to_vxmls(
  writerlys: List(Writerly)
) -> List(VXML) {
  writerlys
  |> list.map(writerly_to_vxml)
}

//***************************
//* assemble_input_lines internals
//***************************

fn file_is_not_commented(path: String) -> Bool {
  !{ string.contains(path, "/#") || string.starts_with(path, "#") }
}

fn has_extension(path: String, exts: List(String)) {
  list.any(exts, string.ends_with(path, _))
}

fn is_parent(path: String) -> Bool {
  string.ends_with(path, "__parent.emu") || string.ends_with(path, "__parent.wly")
}

fn file_is_parent_or_is_selected(
  path_selectors: List(String),
  path: String,
) -> Bool {
  is_parent(path)
  || path_selectors == []
  || list.any(path_selectors, string.contains(path, _))
}

fn file_is_not_parent_or_has_selected_descendant_or_is_selected(
  path_selectors: List(String),
  selected_with_unwanted_parents: List(String),
  path: String,
) -> Bool {
  !is_parent(path)
  || path_selectors == []
  || list.any(path_selectors, string.contains(path, _))
  || list.any(
    selected_with_unwanted_parents,
    fn(x) {
      // is a descendant of ours:
      string.starts_with(x, path |> string.drop_end(string.length("__parent.wly"))) &&
      // ...and is selected:
      list.any(path_selectors, string.contains(x, _))
    }
  )
}

fn parent_path_without_extension(path: String) -> String {
  let pieces = string.split(path, "/") |> list.reverse
  case pieces {
    [] -> "wut?"
    [_, ..rest] -> string.join(list.reverse(rest), "/") <> "/__parent."
  }
}

fn depth_in_directory_tree(path: String, dirname: String) -> Int {
  {
    path
    |> string.drop_start(string.length(dirname) + 1)
    |> string.split("/")
    |> list.length
  }
  - 1
}

fn zero_one(b: Bool) -> Int {
  case b {
    True -> 1
    False -> 0
  }
}

fn add_tree_depth(path: String, dirname: String) -> #(Int, String) {
  let base_depth = depth_in_directory_tree(path, dirname)
  let would_be_parent_path = parent_path_without_extension(path)
  let must_add_1 = {
    {
      { simplifile.is_file(would_be_parent_path <> "emu") |> result.unwrap(False) } ||
      { simplifile.is_file(would_be_parent_path <> "wly") |> result.unwrap(False) }
    }
    && !is_parent(path)
  }
  #(base_depth + zero_one(must_add_1), path)
}

fn shortname_for_blame(path: String, dirname: String) -> String {
  let length_to_drop = case string.ends_with(dirname, "/") || dirname == "" {
    True -> string.length(dirname)
    False -> string.length(dirname) + 1
  }
  string.drop_start(path, length_to_drop)
}

fn input_lines_for_file_at_depth(
  pair: #(Int, String),
  dirname: String,
) -> Result(List(InputLine), AssemblyError) {
  let #(depth, path) = pair
  let shortname = shortname_for_blame(path, dirname)
  case shortname == "" {
    True ->
      panic as {
        "no shortname left after removing dirname '"
        <> dirname
        <> "' from path '"
        <> path
        <> "'"
      }
    False -> shortname
  }

  case simplifile.read(path) {
    Ok(string) -> {
      Ok(io_l.string_to_input_lines(string, shortname, 4 * depth))
    }
    Error(_) -> {
      Error(ReadFileError(path))
    }
  }
}

fn get_files(
  dirname: String,
) -> Result(#(Bool, List(String)), simplifile.FileError) {
  case simplifile.get_files(dirname) {
    Ok(files) ->
      Ok(#(
        True,
        files |> list.filter(fn(file) {string.ends_with(file, ".wly") || string.ends_with(file, ".emu")}),
      ))
    Error(simplifile.Enotdir) -> Ok(#(False, [dirname]))
    Error(error) -> Error(error)
  }
}

fn dir_and_filename(path: String) -> #(String, String) {
  let reversed_path = path |> string.reverse
  let #(reversed_filename, reversed_dir) =
    reversed_path
    |> string.split_once("/")
    |> result.unwrap(#(reversed_path, ""))
  #(reversed_dir |> string.reverse, reversed_filename |> string.reverse)
}

fn filename_compare(f1: String, f2: String) {
  case is_parent(f1) {
    True -> order.Lt
    False -> {
      case is_parent(f2) {
        True -> order.Gt
        False -> string.compare(f1, f2)
      }
    }
  }
}

fn lexicographic_sort_but_parent_comes_first(
  path1: String,
  path2: String,
) -> order.Order {
  let #(dir1, f1) = dir_and_filename(path1)
  let #(dir2, f2) = dir_and_filename(path2)
  let dir_order = string.compare(dir1, dir2)
  case dir_order {
    order.Eq -> filename_compare(f1, f2)
    _ -> dir_order
  }
}

fn has_duplicate(l: List(String)) -> Option(String) {
  case l {
    [] -> None
    [first, ..rest] -> {
      case list.contains(rest, first) {
        True -> Some(first)
        False -> has_duplicate(rest)
      }
    }
  }
}

fn check_no_duplicate_files(files: List(String)) -> Result(Nil, AssemblyError) {
  let files =
    files
    |> list.map(string.drop_end(_, 4))
  case has_duplicate(files) {
    Some(dup) -> Error(TwoFilesSameName(dup <> ".emu has both .emu & .wly versions"))
    None -> Ok(Nil)
  }
}

fn drop_slash(s: String) {
  case string.ends_with(s, "/") {
    True -> string.drop_end(s, 1)
    False -> string.drop_end(s, 0)
  }
}

pub fn assemble_input_lines_advanced_mode(
  dirname: String,
  path_selectors: List(String),
) -> Result(#(List(String), List(InputLine)), AssemblyError) {
  let dirname = drop_slash(dirname)
  case get_files(dirname) {
    Ok(#(was_dir, files)) -> {
      let selected_with_unwanted_parents =
        files
        |> list.filter(has_extension(_, [".emu", ".wly"]))
        |> list.filter(file_is_not_commented)
        |> list.filter(file_is_parent_or_is_selected(path_selectors, _))

      let sorted =
        selected_with_unwanted_parents
        |> list.filter(
          file_is_not_parent_or_has_selected_descendant_or_is_selected(
            path_selectors,
            selected_with_unwanted_parents,
            _,
          ),
        )
        |> list.sort(lexicographic_sort_but_parent_comes_first)

      use _ <- on.ok(check_no_duplicate_files(sorted))

      let tree = 
        sorted
        |> list.map(string.drop_start(_, string.length(dirname) + 1))
        |> dt.directory_tree_from_dir_and_paths(dirname, _, False)
        |> dt.pretty_printer

      use lines <- on.ok(
        sorted
        |> list.map(add_tree_depth(_, dirname))
        |> list.map(
          input_lines_for_file_at_depth(
            _,
            case was_dir {
              True -> dirname
              False -> ""
            }
          ),
        )
        |> result.all
        |> result.map(list.flatten)
      )

      Ok(#(tree, lines))
    }

    Error(_) -> Error(ReadFileOrDirectoryError(dirname))
  }
}

//***************************
//* assemble_input_lines
//***************************

pub fn assemble_input_lines(
  dirname: String,
) -> Result(#(List(String), List(InputLine)), AssemblyError) {
  assemble_input_lines_advanced_mode(dirname, [])
}

// ************************************************************
// assemble_and_parse
// ************************************************************

pub fn assemble_and_parse(
  dir_or_filename: String,
) -> Result(List(Writerly), AssemblyOrParseError) {
  use #(_, assembled) <- on.error_ok(
    assemble_input_lines(dir_or_filename),
    fn(e) { Error(AssemblyError(e)) },
  )

  use writerlys <- on.error_ok(
    parse_input_lines(assembled),
    fn(e) { Error(ParseError(e)) },
  )

  Ok(writerlys)
}

// ************************************************************
// vxml to writerly (canonical transformation) (?)
// ************************************************************

fn is_whitespace(s: String) -> Bool {
  string.trim(s) == ""
}

fn escape_left_spaces_in_string(s: String) -> String {
  let m = string.trim_start(s)
  let n = string.length(s) - string.length(m)
  case n > 0 {
    True -> "\\" <> string.repeat(" ", n) <> m
    False -> m
  }
}

fn escape_left_spaces(
  contents: List(Line),
) -> List(Line) {
  list.map(contents, fn(line) {
    Line(
      line.blame,
      line.content |> escape_left_spaces_in_string,
    )
  })
}

fn process_vxml_t_node(vxml: VXML) -> List(Writerly) {
  let assert T(_, lines) = vxml
  lines
  |> list.index_map(fn(line, i) { #(i, line) })
  |> list.filter(fn(pair) {
    let #(index, line) = pair
    !is_whitespace(line.content)
    || index == 0
    || index == list.length(lines) - 1
  })
  |> list.map(pair.second)
  |> escape_left_spaces
  |> fn(lines) {
    case lines {
      [] -> []
      [first, ..] -> [Blurb(first.blame, lines)]
    }
  }
}

fn is_t(vxml: VXML) -> Bool {
  case vxml {
    T(_, _) -> True
    _ -> False
  }
}

pub fn vxml_to_writerlys(vxml: VXML) -> List(Writerly) { // it would 'Writerly' not 'List(Writerly)' if for the fact that someone could give an empty text node
  case vxml {
    V(blame, tag, attrs, children) -> {
      case tag {
        "WriterlyBlankLine" -> {
          assert attrs == []
          assert children == []
          [BlankLine(blame)]
        }
        "WriterlyCodeBlock" -> {
          assert list.all(children, is_t)
          let lines =
            children
            |> list.flat_map(
              fn(t) {
                let assert T(_, lines) = t
                lines
              }
            )
          [CodeBlock(blame, attrs, lines)]
        }
        _ -> {
          let children = children |> vxmls_to_writerlys
          [Tag(blame, tag, attrs, children)]
        }
      }
    }
    T(_, _) -> {
      vxml |> process_vxml_t_node
    }
  }
}

pub fn vxmls_to_writerlys(vxmls: List(VXML)) -> List(Writerly) {
  vxmls
  |> list.map(vxml_to_writerlys)
  |> list.flatten
}

pub fn vxml_to_writerly(vxml: VXML) -> Result(Writerly, Nil) {
  case vxml |> vxml_to_writerlys {
    [one] -> Ok(one)
    [] -> Error(Nil)
    _ -> panic as "expecting 0 or 1 writerlys"
  }
}
