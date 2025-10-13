import gleam/io
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/regexp
import gleam/result
import gleam/string.{inspect as ins}
import blame.{type Blame, Src, prepend_comment as pc} as bl
import io_lines.{type InputLine, InputLine, type OutputLine, OutputLine} as io_l
import simplifile
import xmlm
import xml_streamer as xs
import on

pub const ampersand_replacer_pattern = "&(?!(?:[a-z]{2,6};|#\\d{2,4};))"

// ************************************************************
// Attr, Line, VXML (pretend 'blame' does not exist -> makes it more readable)
// ************************************************************

pub type Attr {
  Attr(blame: Blame, key: String, val: String)
}

pub type Line {
  Line(blame: Blame, content: String)
}

pub type VXML {
  V(blame: Blame, tag: String, attrs: List(Attr), children: List(VXML))
  T(blame: Blame, lines: List(Line))
}

// ************************************************************
// more public types
// ************************************************************

pub type VXMLParseError {
  VXMLParseErrorEmptyTag(Blame)
  VXMLParseErrorIllegalTagCharacter(Blame, String, String)
  VXMLParseErrorIllegalAttrKeyCharacter(Blame, String, String)
  VXMLParseErrorIndentationTooLarge(Blame, String)
  VXMLParseErrorIndentationNotMultipleOfFour(Blame, String)
  VXMLParseErrorTextMissing(Blame)
  VXMLParseErrorTextNoClosingQuote(Blame, String)
  VXMLParseErrorTextNoOpeningQuote(Blame, String)
  VXMLParseErrorTextOutOfPlace(Blame, String)
  VXMLParseErrorCaretExpected(Blame, String)
  VXMLParseErrorNonUniqueRoot(Int)
}

pub type VXMLParseFileError {
  IOError(simplifile.FileError)
  DocumentError(VXMLParseError)
}

pub type BadTagName {
  EmptyTag
  IllegalTagCharacter(String, String)
}

// ************************************************************
// private types & constants
// ************************************************************

const vxml_indent = 2
const debug_messages = False
const tag_illegal_characters = ["-", ".", " ", "\""]
const attr_key_illegal_characters = [".", ";", "\"", " "]

type FileHead =
  List(InputLine)

type TentativeTagName =
  Result(String, BadTagName)

type BadAttrKey {
  IllegalAttrKeyCharacter(String, String)
}

type TentativeAttrKey =
  Result(String, BadAttrKey)

type TentativeAttr {
  TentativeAttr(
    blame: Blame,
    key: TentativeAttrKey,
    val: String,
  )
}

type NonemptySuffixDiagnostic {
  EmptyCaret
  TaggedCaret(tag: String)
  DoubleQuoted(with_double_quotes: String)
  Other(String)
}

type TentativeVXML {
  TentativeT(blame: Blame, lines: List(Line))
  TentativeV(
    blame: Blame,
    tag: TentativeTagName,
    attrs: List(TentativeAttr),
    children: List(TentativeVXML),
  )
  TentativeErrorIndentationTooLarge(blame: Blame, message: String)
  TentativeErrorIndentationNotMultipleOfFour(blame: Blame, message: String)
  TentativeErrorTextMissing(blame: Blame)
  TentativeErrorTextNoClosingQuote(blamd: Blame, message: String)
  TentativeErrorTextNoOpeningQuote(blamd: Blame, message: String)
  TentativeErrorTextOutOfPlace(blame: Blame, message: String)
  TentativeErrorCaretExpected(blame: Blame, message: String)
}

// ************************************************************
// FileHead-related
// ************************************************************

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

// ************************************************************
// List(InputLine) -> Tentative
// ************************************************************

fn is_double_quoted_thing(suffix: String) -> Bool {
  let trimmed = string.trim(suffix)
  string.starts_with(trimmed, "\"") &&
  string.ends_with(trimmed, "\"") &&
  string.length(trimmed) >= 2
}

fn nonempty_suffix_diagnostic(suffix: String) -> NonemptySuffixDiagnostic {
  assert suffix != ""
  assert !string.starts_with(suffix, " ")

  case string.starts_with(suffix, "<>") {
    True -> {
      let tag = string.trim(string.drop_start(suffix, 2))
      case tag == "" {
        True -> EmptyCaret
        False -> TaggedCaret(tag)
      }
    }

    False ->
      case is_double_quoted_thing(suffix) {
        True -> DoubleQuoted(string.trim(suffix))
        False -> Other(suffix)
      }
  }
}

fn fast_forward_past_lines_of_indent_at_least(
  indent: Int,
  head: FileHead,
) -> #(List(InputLine), FileHead) {
  case current_line(head) {
    None -> #([], head)

    Some(InputLine(_, suffix_indent, _) as first_line) -> {
      case suffix_indent < indent {
        True -> #([], head)

        False -> {
          let #(further_lines, last_head) =
            fast_forward_past_lines_of_indent_at_least(
              indent,
              move_forward(head),
            )

          #([first_line, ..further_lines], last_head)
        }
      }
    }
  }
}

fn tentative_attr(
  blame: Blame,
  pair: #(String, String),
) -> TentativeAttr {
  let #(key, val) = pair
  assert !string.is_empty(key)
  let bad_character = contains_one_of(key, attr_key_illegal_characters)

  case bad_character == "" {
    True -> TentativeAttr(blame: blame, key: Ok(key), val: val)

    False ->
      TentativeAttr(
        blame: blame,
        key: Error(IllegalAttrKeyCharacter(key, bad_character)),
        val: val,
      )
  }
}

fn fast_forward_past_attr_lines_at_indent(
  indent: Int,
  head: FileHead,
) -> #(List(TentativeAttr), FileHead) {
  case current_line(head) {
    None -> #([], head)

    Some(InputLine(blame, suffix_indent, suffix)) -> {
      case suffix == "" {
        True -> #([], move_forward(head))

        False -> {
          case suffix_indent == indent {
            False -> #([], head)

            True ->
              case string.starts_with(suffix, "<>") {
                True -> #([], head)

                False -> {
                  let tentative_attr_pair =
                    suffix
                    |> string.split_once("=")
                    |> result.unwrap(#(suffix, ""))
                    |> tentative_attr(blame, _)

                  let #(more_attr_pairs, head_after_attrs) =
                    fast_forward_past_attr_lines_at_indent(
                      indent,
                      move_forward(head),
                    )

                  #(
                    [tentative_attr_pair, ..more_attr_pairs],
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

fn strip_quotes(s: String) -> String {
  assert string.starts_with(s, "\"")
  assert string.ends_with(s, "\"")
  assert string.length(s) >= 2
  s |> string.drop_start(1) |> string.drop_end(1)
}

fn add_quotes(s: String) -> String {
  "\"" <> s <> "\""
}

fn fast_forward_past_double_quoted_lines_at_indent(
  indent: Int,
  head: FileHead,
) -> #(List(Line), FileHead) {
  case current_line(head) {
    None -> #([], head)

    Some(InputLine(blame, suffix_indent, suffix)) -> {
      case suffix == "" {
        True -> #([], head)

        False -> {
          case suffix_indent != indent {
            True -> #([], head)

            False ->
              case is_double_quoted_thing(suffix) {
                False -> #([], head)

                True -> {
                  let double_quoted =
                    Line(blame, strip_quotes(string.trim(suffix)))

                  let #(more_double_quoteds, head_after_double_quoteds) =
                    fast_forward_past_double_quoted_lines_at_indent(
                      indent,
                      move_forward(head),
                    )

                  #(
                    [double_quoted, ..more_double_quoteds],
                    head_after_double_quoteds,
                  )
                }
              }
          }
        }
      }
    }
  }
}

fn contains_one_of(thing: String, substrings: List(String)) -> String {
  case substrings {
    [] -> ""

    [first, ..rest] -> {
      case string.contains(thing, first) {
        True -> first
        False -> contains_one_of(thing, rest)
      }
    }
  }
}

pub fn validate_tag(tag: String) -> Result(String, BadTagName) {
  case tag == "" {
    True -> Error(EmptyTag)
    False -> {
      let bad_char = contains_one_of(tag, tag_illegal_characters)
      case bad_char == "" {
        True -> Ok(tag)
        False -> Error(IllegalTagCharacter(tag, bad_char))
      }
    }
  }
}

fn assign_error_in_would_be_text_at_indent(
  indent: Int,
  line: InputLine,
) -> TentativeVXML {
  let InputLine(blame, suffix_indent, suffix) = line
  case suffix_indent == indent {
    False ->
      case suffix_indent % vxml_indent == 0 {
        True -> TentativeErrorIndentationTooLarge(blame, suffix)
        False -> TentativeErrorIndentationTooLarge(blame, suffix)
      }
    True -> {
      case string.starts_with(suffix, "\"") {
        False -> TentativeErrorTextNoOpeningQuote(blame, suffix)
        True -> {
          case is_double_quoted_thing(suffix) {
            False -> TentativeErrorTextNoClosingQuote(blame, suffix)
            True -> TentativeErrorTextOutOfPlace(blame, suffix)
          }
        }
      }
    }
  }
}

fn assign_errors_in_would_be_text_at_indent(
  indent: Int,
  lines: List(InputLine),
) -> List(TentativeVXML) {
  list.map(lines, assign_error_in_would_be_text_at_indent(indent, _))
}

fn continue_parsing(
  element: TentativeVXML,
  indent: Int,
  head: FileHead,
) -> #(List(TentativeVXML), FileHead) {
  let #(other_elements, head_after_indent) =
    tentative_parse_at_indent(indent, head)

  #([element, ..other_elements], head_after_indent)
}

fn continue_parsing_many(
  elements: List(TentativeVXML),
  indent: Int,
  head: FileHead,
) -> #(List(TentativeVXML), FileHead) {
  let #(other_elements, head_after_indent) =
    tentative_parse_at_indent(indent, head)

  #(list.flatten([elements, other_elements]), head_after_indent)
}

fn tentative_parse_at_indent(
  indent: Int,
  head: FileHead,
) -> #(List(TentativeVXML), FileHead) {
  case current_line(head) {
    None -> #([], head)

    Some(InputLine(blame, suffix_indent, suffix)) -> {
      case suffix == "" {
        True -> tentative_parse_at_indent(indent, move_forward(head))

        False -> {
          case suffix_indent < indent {
            True -> {
              case suffix_indent > indent - vxml_indent {
                True -> {
                  let error =
                    TentativeErrorIndentationNotMultipleOfFour(blame, suffix)

                  continue_parsing(error, indent, move_forward(head))
                }

                False -> #([], head)
              }
            }

            False ->
              case suffix_indent > indent {
                True -> {
                  let #(_, head_after_oversize_indent) =
                    fast_forward_past_lines_of_indent_at_least(
                      suffix_indent,
                      head,
                    )

                  let error = case suffix_indent % vxml_indent == 0 {
                    True -> {
                      let error_message =
                        "(" <> ins(suffix_indent) <> " > " <> ins(indent) <> ")"

                      TentativeErrorIndentationTooLarge(
                        blame,
                        error_message <> suffix,
                      )
                    }

                    False ->
                      TentativeErrorIndentationNotMultipleOfFour(blame, suffix)
                  }

                  continue_parsing(error, indent, head_after_oversize_indent)
                }

                False -> {
                  assert suffix_indent == indent

                  case nonempty_suffix_diagnostic(suffix) {
                    TaggedCaret(annotation) -> {
                      let #(tentative_attrs, head_after_attrs) =
                        fast_forward_past_attr_lines_at_indent(
                          indent + vxml_indent,
                          move_forward(head),
                        )

                      let #(children, remaining_after_children) =
                        tentative_parse_at_indent(
                          indent + vxml_indent,
                          head_after_attrs,
                        )

                      let tentative_tag =
                        TentativeV(
                          blame: blame,
                          tag: validate_tag(string.trim(annotation)),
                          attrs: tentative_attrs,
                          children: children,
                        )

                      continue_parsing(
                        tentative_tag,
                        indent,
                        remaining_after_children,
                      )
                    }

                    EmptyCaret -> {
                      let #(indented_lines, remaining_after_indented_lines) =
                        fast_forward_past_lines_of_indent_at_least(
                          indent + vxml_indent,
                          move_forward(head),
                        )

                      let #(double_quoted_at_correct_indent, others) =
                        fast_forward_past_double_quoted_lines_at_indent(
                          indent + vxml_indent,
                          indented_lines,
                        )

                      let text_node_or_error = case
                        list.is_empty(double_quoted_at_correct_indent)
                      {
                        True -> TentativeErrorTextMissing(blame)
                        False ->
                          TentativeT(
                            blame: blame,
                            lines: double_quoted_at_correct_indent,
                          )
                      }

                      let error_siblings =
                        assign_errors_in_would_be_text_at_indent(
                          indent + vxml_indent,
                          others,
                        )

                      continue_parsing_many(
                        [text_node_or_error, ..error_siblings],
                        indent,
                        remaining_after_indented_lines,
                      )
                    }

                    DoubleQuoted(text) -> {
                      let error = TentativeErrorTextOutOfPlace(blame, text)
                      continue_parsing(error, indent, move_forward(head))
                    }

                    Other(something) -> {
                      let error = TentativeErrorCaretExpected(blame, something)
                      continue_parsing(error, indent, move_forward(head))
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

// ************************************************************
// Tentative -> VXML
// ************************************************************

fn tentative_attr_to_attr(
  t: TentativeAttr,
) -> Result(Attr, VXMLParseError) {
  case t.key {
    Ok(key) -> Ok(Attr(blame: t.blame, key: key, val: t.val))

    Error(IllegalAttrKeyCharacter(original_would_be_key, bad_char)) ->
      Error(VXMLParseErrorIllegalAttrKeyCharacter(
        t.blame,
        original_would_be_key,
        bad_char,
      ))
  }
}

fn tentative_attrs_to_attrs(
  attrs: List(TentativeAttr),
) -> Result(List(Attr), VXMLParseError) {
  case attrs {
    [] -> Ok([])
    [first, ..rest] ->
      case tentative_attr_to_attr(first) {
        Error(error) -> Error(error)
        Ok(attr) ->
          case tentative_attrs_to_attrs(rest) {
            Ok(attrs) -> Ok([attr, ..attrs])

            Error(error) -> Error(error)
          }
      }
  }
}

fn parse_from_tentatives(
  tentatives: List(TentativeVXML),
) -> Result(List(VXML), VXMLParseError) {
  case tentatives {
    [] -> Ok([])
    [first, ..rest] ->
      case parse_from_tentative(first) {
        Ok(parsed) ->
          case parse_from_tentatives(rest) {
            Ok(parseds) -> Ok([parsed, ..parseds])

            Error(error) -> Error(error)
          }

        Error(error) -> Error(error)
      }
  }
}

fn parse_from_tentative(
  tentative: TentativeVXML,
) -> Result(VXML, VXMLParseError) {
  case tentative {
    TentativeErrorIndentationTooLarge(blame, message) ->
      Error(VXMLParseErrorIndentationTooLarge(blame, message))

    TentativeErrorIndentationNotMultipleOfFour(blame, message) ->
      Error(VXMLParseErrorIndentationNotMultipleOfFour(blame, message))

    TentativeErrorTextMissing(blame) -> Error(VXMLParseErrorTextMissing(blame))

    TentativeErrorTextNoClosingQuote(blame, message) ->
      Error(VXMLParseErrorTextNoClosingQuote(blame, message))

    TentativeErrorTextNoOpeningQuote(blame, message) ->
      Error(VXMLParseErrorTextNoOpeningQuote(blame, message))

    TentativeErrorTextOutOfPlace(blame, message) ->
      Error(VXMLParseErrorTextOutOfPlace(blame, message))

    TentativeErrorCaretExpected(blame, message) ->
      Error(VXMLParseErrorCaretExpected(blame, message))

    TentativeT(blame, lines) -> Ok(T(blame, lines))

    TentativeV(blame, tentative_name, tentative_attrs, tentative_children) ->
      case tentative_name {
        Error(EmptyTag) -> Error(VXMLParseErrorEmptyTag(blame))

        Error(IllegalTagCharacter(original_bad_name, bad_char)) ->
          Error(VXMLParseErrorIllegalTagCharacter(
            blame,
            original_bad_name,
            bad_char,
          ))

        Ok(name) ->
          case
            tentative_attrs_to_attrs(
              tentative_attrs,
            )
          {
            Error(error) -> Error(error)

            Ok(attrs) ->
              case parse_from_tentatives(tentative_children) {
                Error(error) -> Error(error)

                Ok(children) ->
                  Ok(V(
                    blame: blame,
                    tag: name,
                    attrs: attrs,
                    children: children,
                  ))
              }
          }
      }
  }
}

fn tentative_parse_input_lines(
  head: FileHead,
) -> List(TentativeVXML) {
  let #(parsed, final_head) = tentative_parse_at_indent(0, head)
  assert list.is_empty(final_head)

  case debug_messages {
    True -> tentatives_table(parsed, "tentative_parsed", 0) |> io.println
    False -> Nil
  }

  parsed
}

// ************************************************************
// Tentative -> List(OutputLine)
// ************************************************************

fn tentative_error_blame_and_type_and_message(
  t: TentativeVXML,
) -> #(Blame, String, String) {
  case t {
    TentativeT(_, _) -> panic as "not an error node"
    TentativeV(_, _, _, _) -> panic as "not an error node"
    TentativeErrorIndentationTooLarge(blame, message) -> #(blame, "IndentationTooLarge", message)
    TentativeErrorIndentationNotMultipleOfFour(blame, message) -> #(blame, "IndentationNotMultipleOfFour", message)
    TentativeErrorCaretExpected(blame, message) -> #(blame, "CareExpected", message)
    TentativeErrorTextMissing(blame) -> #(blame, "TextMissing", "")
    TentativeErrorTextNoClosingQuote(blame, message) -> #(blame, "TextNoClosingQuote", message)
    TentativeErrorTextNoOpeningQuote(blame, message) -> #(blame, "TextNoOpeningQuote", message)
    TentativeErrorTextOutOfPlace(blame, message) -> #(blame, "TextOutOfPlace", message)
  }
}

fn tentative_to_output_lines_internal(
  t: TentativeVXML,
  indentation: Int,
) -> List(OutputLine) {
  case t {
    TentativeT(blame, lines) -> {
      [
        OutputLine(blame, indentation, "<>"),
        ..list.map(lines, fn(line) -> OutputLine {
          OutputLine(
            line.blame,
            indentation + vxml_indent,
            line.content,
          )
        })
      ]
    }

    TentativeV(
      blame,
      Ok(_) as tag_result,
      tentative_attrs,
      children,
    ) -> {
      [
        OutputLine(blame, indentation, "<> " <> ins(tag_result)),
        ..list.flatten([
          list.map(tentative_attrs, fn(tentative_attr) {
            OutputLine(
              tentative_attr.blame,
              indentation + vxml_indent,
              ins(tentative_attr.key)
                <> " "
                <> tentative_attr.val,
            )
          }),
          tentatives_to_output_lines_internal(children, indentation + vxml_indent),
        ])
      ]
    }

    TentativeV(blame, Error(err), tentative_attrs, children) -> {
      [
        OutputLine(
          blame |> pc("ERROR BadTagName"),
          indentation,
          "<> " <> ins(err),
        ),
        ..list.flatten([
          list.map(tentative_attrs, fn(tentative_attr) {
            OutputLine(
              tentative_attr.blame,
              indentation + vxml_indent,
              ins(tentative_attr.key)
                <> " "
                <> tentative_attr.val,
            )
          }),
          tentatives_to_output_lines_internal(children, indentation + vxml_indent),
        ])
      ]
    }

    _ -> {
      let #(blame, error_type, message) =
        tentative_error_blame_and_type_and_message(t)
      [OutputLine(blame |> pc("ERROR " <> error_type), indentation, message)]
    }
  }
}

fn tentatives_to_output_lines_internal(
  tentatives: List(TentativeVXML),
  indentation: Int,
) -> List(OutputLine) {
  tentatives
  |> list.map(tentative_to_output_lines_internal(_, indentation))
  |> list.flatten
}

fn tentatives_table(tentatives: List(TentativeVXML), banner: String, indent: Int) -> String {
  tentatives
  |> tentatives_to_output_lines_internal(0)
  |> io_l.output_lines_table(banner, indent)
}

// ************************************************************
// debug annotating VXML blames (esoteric)
// ************************************************************

pub fn annotate_blames(vxml: VXML) -> VXML {
  case vxml {
    T(blame, lines) -> {
      T(
        blame |> pc("T"),
        list.index_map(lines, fn(line, i) {
          Line(
            line.blame
              |> pc("T > Line(" <> ins(i + 1) <> ")"),
            line.content,
          )
        }),
      )
    }
    V(blame, tag, attrs, children) -> {
      V(
        blame |> pc("V"),
        tag,
        list.index_map(attrs, fn(attr, i) {
          Attr(
            attr.blame |> pc("Attr(" <> ins(i + 1) <> ")"),
            attr.key,
            attr.val,
          )
        }),
        list.map(children, annotate_blames),
      )
    }
  }
}

// ************************************************************
// VXML -> List(OutputLine)
// ************************************************************

fn vxml_to_output_lines_internal(
  vxml: VXML,
  indentation: Int,
) -> List(OutputLine) {
  case vxml {
    T(blame, lines) -> [
      OutputLine(blame, indentation, "<>"),
      ..list.map(lines, fn(line) {
        OutputLine(
          line.blame,
          indentation + vxml_indent,
          add_quotes(line.content),
        )
      })
    ]

    V(blame, tag, attrs, children) -> {
      [
        OutputLine(blame, indentation, "<> " <> tag),
        ..list.append(
          list.map(attrs, fn(attr) {
            OutputLine(
              attr.blame,
              indentation + vxml_indent,
              attr.key <> "=" <> attr.val,
            )
          }),
          children
          |> list.map(vxml_to_output_lines_internal(_, indentation + 2))
          |> list.flatten
        )
      ]
    }
  }
}


// ************************************************************
// VXML -> List(OutputLine) api
// ************************************************************

pub fn vxml_to_output_lines(vxml: VXML) -> List(OutputLine) {
  vxml_to_output_lines_internal(vxml, 0)
}

pub fn vxmls_to_output_lines(vxmls: List(VXML)) -> List(OutputLine) {
  vxmls
  |> list.map(vxml_to_output_lines)
  |> list.flatten
}

// ************************************************************
// VXML -> String api
// ************************************************************

pub fn vxml_to_string(vxml: VXML) -> String {
  vxml
  |> vxml_to_output_lines
  |> io_l.output_lines_to_string
}

pub fn vxmls_to_string(vxmls: List(VXML)) -> String {
  vxmls
  |> vxmls_to_output_lines
  |> io_l.output_lines_to_string
}

// ************************************************************
// echo_vxml
// ************************************************************

pub fn vxml_table(vxml: VXML, banner: String, indent: Int) -> String {
  vxml
  |> vxml_to_output_lines
  |> io_l.output_lines_table(banner, indent)
}

// ************************************************************
// VXML -> jsx
// ************************************************************

fn jsx_string_processor(content: String, ampersand_replacer: regexp.Regexp) -> String {
  content
  |> regexp.replace(ampersand_replacer, _, "&amp;")
  |> string.replace("{", "&#123;")
  |> string.replace("}", "&#125;")
  |> string.replace("<", "&lt;")
  |> string.replace(">", "&gt;")
}

fn jsx_key_val(
  attr: Attr,
  ampersand_replacer: regexp.Regexp,
) -> String {
  let val = string.trim(attr.val) |> jsx_string_processor(ampersand_replacer)
  case val == "false" || val == "true" || result.is_ok(int.parse(val)) {
    True -> attr.key <> "={" <> val <> "}"
    False -> attr.key <> "=\"" <> val <> "\""
  }
}

fn jsx_attr_output_line(
  attr: Attr,
  indent: Int,
  ampersand_replacer: regexp.Regexp,
) -> OutputLine {
  OutputLine(
    blame: attr.blame,
    indent: indent,
    suffix: jsx_key_val(attr, ampersand_replacer)
  )
}

fn jsx_tag_close_output_lines(
  blame: Blame,
  tag: String,
  indent: Int,
) -> List(OutputLine) {
  [OutputLine(blame: blame, indent: indent, suffix: "</" <> tag <> ">")]
}

fn jsx_tag_open_output_lines(
  blame: Blame,
  tag: String,
  indent: Int,
  closing: String,
  attrs: List(Attr),
  ampersand_replacer: regexp.Regexp,
) -> List(OutputLine) {
  case attrs {
    [] -> [
      OutputLine(blame: blame, indent: indent, suffix: "<" <> tag <> closing),
    ]
    [first] -> [
      OutputLine(
        blame: blame,
        indent: indent,
        suffix: "<" <> tag <> " " <> jsx_key_val(first, ampersand_replacer) <> closing,
      ),
    ]
    _ -> {
      [
        [OutputLine(blame: blame, indent: indent, suffix: "<" <> tag)],
        attrs |> list.map(jsx_attr_output_line(_, indent, ampersand_replacer)),
        [OutputLine(blame: blame, indent: indent, suffix: closing)],
      ]
      |> list.flatten
    }
  }
}

fn bool_2_jsx_space(b: Bool) -> String {
  case b {
    True -> "{\" \"}"
    False -> ""
  }
}

fn vxml_to_jsx_output_lines_internal(
  vxml: VXML,
  indent: Int,
  ampersand_replacer: regexp.Regexp,
) -> List(OutputLine) {
  case vxml {
    T(_, lines) -> {
      let n = list.length(lines)
      lines
      |> list.index_map(fn(t, i) {
        OutputLine(blame: t.blame, indent: indent, suffix: {
          let content = jsx_string_processor(t.content, ampersand_replacer)
          let start = {i == 0 && {string.starts_with(content, " ") || string.is_empty(content)}} |> bool_2_jsx_space
          let end = {i == n - 1 && {string.ends_with(content, " ") || string.is_empty(content)}} |> bool_2_jsx_space
          start <> content <> end
        })
      })
    }

    V(blame, tag, attrs, children) -> {
      case list.is_empty(children) {
        False ->
          [
            jsx_tag_open_output_lines(blame, tag, indent, ">", attrs, ampersand_replacer),
            children
            |> list.map(vxml_to_jsx_output_lines_internal(_, indent + 2, ampersand_replacer))
            |> list.flatten,
            jsx_tag_close_output_lines(blame, tag, indent),
          ]
          |> list.flatten

        True ->
          jsx_tag_open_output_lines(blame, tag, indent, " />", attrs, ampersand_replacer)
      }
    }
  }
}

// ************************************************************
// VXML -> jsx blamed lines
// ************************************************************

pub fn vxml_to_jsx_output_lines(vxml: VXML, indent: Int) -> List(OutputLine) {
  // a regex that matches ampersands that appear outside of html entities:
  let assert Ok(ampersand_replacer) = regexp.from_string(ampersand_replacer_pattern)
  vxml_to_jsx_output_lines_internal(vxml, indent, ampersand_replacer)
}

pub fn vxmls_to_jsx_output_lines(vxmls: List(VXML), indent: Int) -> List(OutputLine) {
  // a regex that matches ampersands that appear outside of html entities:
  let assert Ok(ampersand_replacer) = regexp.from_string(ampersand_replacer_pattern)
  vxmls
  |> list.map(vxml_to_jsx_output_lines_internal(_, indent, ampersand_replacer))
  |> list.flatten
}

// ************************************************************
// VXML -> jsx string
// ************************************************************

pub fn vxml_to_jsx(vxml: VXML, indent: Int) -> String {
  vxml
  |> vxml_to_jsx_output_lines(indent)
  |> io_l.output_lines_to_string
}

pub fn vxmls_to_jsx(vxmls: List(VXML), indent: Int) -> String {
  vxmls
  |> vxmls_to_jsx_output_lines(indent)
  |> io_l.output_lines_to_string
}

// ************************************************************
// VXML -> html
// ************************************************************

fn html_string_processor(content: String, ampersand_replacer: regexp.Regexp) -> String {
  content
  |> regexp.replace(ampersand_replacer, _, "&amp;")
  |> string.replace("<", "&lt;")
  |> string.replace(">", "&gt;")
}

type StickyLine {
  StickyLine(
    blame: Blame,
    indent: Int,
    content: String,
    sticky_start: Bool,
    sticky_end: Bool,
  )
}

type StickyTree {
  StickyTree(
    opening_lines: List(StickyLine),
    children: List(StickyTree),
    closing_lines: List(StickyLine),
  )
}

fn sticky_2_blamed(stickie: StickyLine) -> OutputLine {
  OutputLine(stickie.blame, stickie.indent, stickie.content)
}

fn concat_sticky_lines_internal(
  already_stuck: List(StickyLine),
  working_on: StickyLine,
  upcoming: List(StickyLine),
) -> List(StickyLine) {
  case upcoming {
    [] -> {
      [working_on, ..already_stuck] |> list.reverse
    }
    [next, ..rest] -> {
      case working_on.sticky_end && next.sticky_start {
        True ->
          concat_sticky_lines_internal(
            already_stuck,
            StickyLine(
              ..working_on,
              content: working_on.content <> next.content,
              sticky_end: next.sticky_end,
            ),
            rest,
          )
        False ->
          concat_sticky_lines_internal(
            [working_on, ..already_stuck],
            next,
            rest,
          )
      }
    }
  }
}

fn concat_sticky_lines(lines: List(StickyLine)) -> List(StickyLine) {
  case lines {
    [] -> []
    [first, ..rest] -> concat_sticky_lines_internal([], first, rest)
  }
}

fn pour(to: List(a), from: List(a)) -> List(a) {
  case from {
    [] -> to
    [first, ..rest] -> pour([first, ..to], rest)
  }
}

fn sticky_trees_2_sticky_lines(
  already_stuck: List(StickyLine),
  subtrees: List(StickyTree),
) -> List(StickyLine) {
  case subtrees {
    [] -> already_stuck
    [first, ..rest] ->
      sticky_trees_2_sticky_lines(
        sticky_tree_2_sticky_lines(already_stuck, first),
        rest,
      )
  }
}

fn sticky_tree_2_sticky_lines(
  already_stuck: List(StickyLine),
  subtree: StickyTree,
) -> List(StickyLine) {
  let StickyTree(opening_lines, children, closing_lines) = subtree
  let already_stuck = pour(already_stuck, opening_lines)
  let already_stuck = sticky_trees_2_sticky_lines(already_stuck, children)
  pour(already_stuck, closing_lines)
}

fn attrs_to_sticky_lines(
  attrs: List(Attr),
  indent: Int,
  inline: Bool,
) -> List(StickyLine) {
  let space = case inline {
    True -> " "
    False -> ""
  }
  attrs
  |> list.map(fn(t) {
    StickyLine(
      blame: t.blame,
      indent: indent,
      content: space <> t.key <> "=\"" <> t.val <> "\"",
      sticky_start: inline,
      sticky_end: inline,
    )
  })
}

const sticky_tags = [
  "NumberedTitle", "a", "span", "i", "b", "strong", "em", "code", "tt", "br", "img",
]

const self_closing_tags = ["img", "br", "hr"]

fn opening_tag_to_sticky_lines(
  t: VXML,
  indent: Int,
  spaces: Int,
  pre: Bool,
) -> List(StickyLine) {
  let assert V(blame, tag, attrs, _) = t
  let indent = case pre {
    True -> 0
    False -> indent
  }
  let sticky_outside = list.contains(sticky_tags, tag)
  let sticky_inside = list.length(attrs) <= 1
  list.flatten([
    [StickyLine(blame, indent, "<" <> tag, sticky_outside, sticky_inside)],
    attrs_to_sticky_lines(attrs, indent + spaces, sticky_inside),
    [StickyLine(blame, indent, ">", sticky_inside, sticky_outside)],
  ])
}

fn closing_tag_to_sticky_lines(
  t: VXML,
  indent: Int,
  pre: Bool,
) -> List(StickyLine) {
  let assert V(blame, tag, _, _) = t
  let indent = case pre {
    True -> 0
    False -> indent
  }
  let sticky_outside = list.contains(sticky_tags, tag)
  [
    StickyLine(
      blame,
      indent,
      "</" <> tag <> ">",
      sticky_outside,
      sticky_outside,
    ),
  ]
}

pub fn init_last(l: List(a)) -> Result(#(List(a), a), Nil) {
  case l {
    [] -> Error(Nil)
    [last] -> Ok(#([], last))
    [first, ..rest] -> {
      let assert Ok(#(head, last)) = init_last(rest)
      Ok(#([first, ..head], last))
    }
  }
}

fn t_sticky_lines(t: VXML, indent: Int, pre: Bool, ampersand_replacer: regexp.Regexp) -> List(StickyLine) {
  let assert T(_, lines) = t
  let indent = case pre {
    True -> 0
    False -> indent
  }
  let last_index = list.length(lines) - 1
  let sticky_lines = list.index_map(
    lines,
    fn(line, i) {
      let content = html_string_processor(line.content, ampersand_replacer)
      StickyLine(
        blame: line.blame,
        indent: indent,
        content: content,
        sticky_start: i == 0 && {!string.starts_with(content, " ") || pre},
        sticky_end: i == last_index && {!string.ends_with(content, " ") || pre},
      )
    }
  )
  // if not pre:
  // - while lines have at least 1 line:
  //   - any starting blanks of first content can be removed (start is automatically non-sticky in that case)
  //   - any ending blanks of last content can be removed (end is automatically non-sticky in that case)
  //   - if first content is empty and at least 2 lines, can remove first
  //   - if last content is empty and at least 2 lines, can remove last
  //   - if first == last content is empty, can make sticky_start = False, sticky_end = True to induce simple newline at that indent
  case pre {
    True -> sticky_lines
    False -> t_very_fancy_sticky_lines_post_processing(sticky_lines)
  }
}

fn t_very_fancy_sticky_lines_post_processing(
  lines: List(StickyLine),
) -> List(StickyLine) {
  // see 'if not pre' comment above for what this function
  // thinks it's doing

  let trim_start = fn(sticky: StickyLine) -> StickyLine {
    StickyLine(..sticky, content: string.trim_start(sticky.content))
  }

  let trim_end = fn(sticky: StickyLine) -> StickyLine {
    StickyLine(..sticky, content: string.trim_end(sticky.content))
  }

  let assert [first, ..rest] = lines

  case string.starts_with(first.content, " ") {
    True -> {
      // action 1: the start is not sticky anyway, so
      // trim starting spaces (this function is never called in 'pre' btw)
      assert first.sticky_start == False
      t_very_fancy_sticky_lines_post_processing([trim_start(first), ..rest])
    }
    False -> {
      case first.content == "" {
        True -> case list.is_empty(rest) {
          False -> {
            // action 2: the next line is not sticky anyway, so drop
            // this empty line and keep only the others
            let assert Ok(new_first) = list.first(rest)
            assert new_first.sticky_start == False
            t_very_fancy_sticky_lines_post_processing(rest)
          }
          True -> {
            // action 3: we have only 1 empty line, make it non-sticky
            // at start and sticky at end to simulate a plain newline
            [StickyLine(..first, sticky_start: False, sticky_end: True)]
          }
        }
        False -> {
          // let assert Ok(#(init, last)) = init_last(lines)
          let assert [last, ..init] = lines |> list.reverse
          case string.ends_with(last.content, " ") {
            True -> {
              // action 4 mirroring action 1: the end is not sticky anyway,
              // so trim ending spaces of last line
              assert last.sticky_end == False
              t_very_fancy_sticky_lines_post_processing(
                [trim_end(last), ..init] |> list.reverse
              )
            }
            False -> {
              case last.content == "" {
                True -> {
                  let assert [new_last, ..] = init
                  assert new_last.sticky_end == False
                  t_very_fancy_sticky_lines_post_processing(init |> list.reverse)
                }
                False -> lines // (could not find anything to change)
              }
            }
          }
        }
      }
    }
  }
}

fn t_sticky_tree(t: VXML, indent: Int, pre: Bool, ampersand_replacer: regexp.Regexp) -> StickyTree {
  StickyTree(
    opening_lines: t_sticky_lines(t, indent, pre, ampersand_replacer),
    children: [],
    closing_lines: [],
  )
}

fn v_sticky_tree(v: VXML, indent: Int, spaces: Int, pre: Bool, ampersand_replacer: regexp.Regexp) -> StickyTree {
  let assert V(_, tag, _, children) = v
  let pre = pre || tag |> string.lowercase == "pre"
  StickyTree(
    opening_lines: opening_tag_to_sticky_lines(v, indent, spaces, pre),
    children: children |> list.map(vxml_sticky_tree(_, indent + spaces, spaces, pre, ampersand_replacer)),
    closing_lines: case list.contains(self_closing_tags, tag) {
      True -> []
      False -> closing_tag_to_sticky_lines(v, indent, pre)
    },
  )
}

fn vxml_sticky_tree(
  node: VXML,
  indent: Int,
  spaces: Int,
  pre: Bool,
  ampersand_replacer: regexp.Regexp,
) -> StickyTree {
  case node {
    T(_, _) -> t_sticky_tree(node, indent, pre, ampersand_replacer)
    V(_, _, _, _) -> v_sticky_tree(node, indent, spaces, pre, ampersand_replacer)
  }
}

pub fn vxml_to_html_output_lines_internal(
  node: VXML,
  indent: Int,
  spaces: Int,
  ampersand_replacer: regexp.Regexp,
) -> List(OutputLine) {
  vxml_sticky_tree(node, indent, spaces, False, ampersand_replacer)
  |> sticky_tree_2_sticky_lines([], _)
  |> list.reverse
  |> concat_sticky_lines
  |> list.map(sticky_2_blamed)
}

pub fn vxmls_to_html_output_lines_internal(
  vxmls: List(VXML),
  indent: Int,
  spaces: Int,
  ampersand_replacer: regexp.Regexp,
) -> List(OutputLine) {
  vxmls
  |> list.map(vxml_to_html_output_lines_internal(_, indent, spaces, ampersand_replacer))
  |> list.flatten
}

pub fn vxml_to_html_output_lines(
  node: VXML,
  indent: Int,
  spaces: Int,
) -> List(OutputLine) {
  let assert Ok(ampersand_replacer) = regexp.from_string(ampersand_replacer_pattern)
  vxml_to_html_output_lines_internal(node, indent, spaces, ampersand_replacer)
}

pub fn vxmls_to_html_output_lines(
  vxmls: List(VXML),
  indent: Int,
  spaces: Int,
) -> List(OutputLine) {
  let assert Ok(ampersand_replacer) = regexp.from_string(ampersand_replacer_pattern)
  vxmls_to_html_output_lines_internal(vxmls, indent, spaces, ampersand_replacer)
}

// ************************************************************
// parse_input_lines
// ************************************************************

pub fn parse_input_lines(
  lines: List(io_l.InputLine),
) -> Result(List(VXML), VXMLParseError) {
  lines
  |> tentative_parse_input_lines
  |> parse_from_tentatives
}

// ************************************************************
// parse_string
// ************************************************************

pub fn parse_string(
  source: String,
  filename: String,
) -> Result(List(VXML), VXMLParseError) {
  source
  |> io_l.string_to_input_lines(filename, 0)
  |> parse_input_lines
}

// ************************************************************
// parse_file
// ************************************************************

pub fn parse_file(
  path: String,
) -> Result(List(VXML), VXMLParseFileError) {
  use contents <- on.error_ok(
    simplifile.read(path),
    fn (io_error) { Error(IOError(io_error)) },
  )

  parse_string(contents, path)
  |> result.map_error(fn(e) { DocumentError(e) })
}

// ************************************************************
// XMLM parser
// ************************************************************

fn xmlm_attr_to_vxml_attrs(
  filename: String,
  line_no: Int,
  xmlm_attr: xmlm.Attribute,
) -> Attr {
  let blame = Src([], filename, line_no, 0)
  Attr(blame, xmlm_attr.name.local, xmlm_attr.value)
}

pub fn xmlm_based_html_parser(
  content: String,
  filename: String,
) -> Result(VXML, xmlm.InputError) {
  // some preliminary cleanup that avoids complaints
  // from the xmlm parser:
  let content = string.replace(content, "\r\n", "\n")
  let content = string.replace(content, "async ", "async=\"\"")
  let content = string.replace(content, "async\n", "async=\"\"\n")
  let content = string.replace(content, "& ", "&amp;")
  let content = string.replace(content, "&\n", "&amp;\n")
  let content = string.replace(content, " &", "&amp;")
  let content = string.replace(content, "\\,<", "\\,&lt;")
  let content = string.replace(content, " < ", " &lt; ")
  let content = string.replace(content, "\\rt{0.1}<", "\\rt{0.1}&lt;")

  // close img tags
  // let assert Ok(re) = regexp.from_string("(<img)(\\b(?![^>]*/\\s*>)[^>]*)(>)") // (old complicated regex... simplified Sep 2025)
  let assert Ok(re) = regexp.from_string("(<img)(\\b[^>]*[^\\/])(>)")
  let content =
    regexp.match_map(re, content, fn(match) {
      let regexp.Match(_, sub) = match
      let assert [_, Some(middle), _] = sub
      "<img" <> middle <> "/>"
    })

  // remove attrs in closing tags
  let assert Ok(re) = regexp.from_string("(<\\/)(\\w+)(\\s+[^>]*)(>)")
  let matches = regexp.scan(re, content)

  let content =
    list.fold(matches, content, fn(content_str, match) {
      let regexp.Match(_, sub) = match
      let assert [_, Some(tag), _, _] = sub
      regexp.replace(re, content_str, "</" <> tag <> ">")
    })

  let input = xmlm.from_string(content)

  // **********
  // use this to debug if you get an input_error on a file, see
  // "input_error" case at end of function
  // **********
  // // case xmlm.signals(
  // //   input
  // // ) {
  // //   Ok(#(signals, _)) -> {
  // //     list.each(
  // //       signals,
  // //       fn(signal) { io.println(signal |> xmlm.signal_to_string) }
  // //     )
  // //   }
  // //   Error(input_error) -> {
  // //     io.println("got error:" <> ins(input_error))
  // //   }
  // // }

  case
    xmlm.document_tree(
      input,
      fn(xmlm_tag, children) {
        V(
          Src([], filename, 0, 0),
          xmlm_tag.name.local,
          xmlm_tag.attributes
            |> list.map(xmlm_attr_to_vxml_attrs(filename, 0, _)),
          children,
        )
      },
      fn(content) {
        let lines =
          content
          |> string.split("\n")
          |> list.map(fn(content) {
            Line(Src([], filename, 0, 0), content)
          })
        T(Src([], filename, 0, 0), lines)
      },
    )
  {
    Ok(#(_, vxml, _)) -> Ok(vxml)
    Error(input_error) -> Error(input_error)
  }
}

// ************************************************************
// XML streaming-based parser
// ************************************************************

pub type XMLStreamingParserLogicalUnit {
  XMLStreamingParserText(List(Line))
  XMLStreamingParserOpeningTag(Blame, String, List(Attr))
  XMLStreamingParserSelfClosingTag(Blame, String, List(Attr))
  XMLStreamingParserXMLVersion(Blame, String, List(Attr))
  XMLStreamingParserDoctype(Blame, String, List(Attr), Bool)
  XMLStreamingParserClosingTag(Blame, String)
  XMLStreamingParserComment(List(Line))
}

fn take_while_text_or_newline_acc(
  previous: List(xs.Event),
  remaining: List(xs.Event),
) -> #(List(xs.Event), List(xs.Event)) {
  // returns reversed list on purpose!!!
  case remaining {
    [] -> #(previous, [])
    [first, ..rest] -> case first {
      xs.Text(_, _) | xs.Newline(_) -> 
        take_while_text_or_newline_acc(
          [first, ..previous],
          rest,
        )
      _ -> #(previous, remaining)
    }
  }
}

fn take_while_text_or_newline(
  events: List(xs.Event)
) -> #(List(xs.Event), List(xs.Event)) {
  // returns reversed list on purpose!!!
  take_while_text_or_newline_acc([], events)
}

type Return(a, b) {
  Return(a)
  Continuation(b)
}

fn on_continuation(
  thing: Return(a, b),
  f: fn(b) -> a,
) -> a {
  case thing {
    Return(a) -> a
    Continuation(b) -> f(b)
  }
}

type TriWay {
  NoMoreEvents
  TagEnd(xs.Event, List(xs.Event))
  SomethingElse(xs.Event, List(xs.Event), Bool)
}

fn tri_way(
  events: List(xs.Event),
) -> TriWay {
  case events {
    [] -> NoMoreEvents
    [first, ..rest] -> {
      case first {
        xs.TagEndOrdinary(_) -> TagEnd(first, rest)
        xs.TagEndSelfClosing(_) -> TagEnd(first, rest)
        xs.TagEndXMLVersion(_) -> TagEnd(first, rest)
        xs.InTagWhitespace(_, _) | xs.Newline(_) -> case tri_way(rest) {
          SomethingElse(first, rest, _) ->
            SomethingElse(first, rest, True)
          x -> x
        }
        _ -> SomethingElse(first, rest, False)
      }
    }
  }
}

fn get_attrs_and_tag_end(
  tag_start: xs.Event,
  rest: List(xs.Event),
) -> Result(
  #(List(Attr), xs.Event, List(xs.Event)), 
  #(Blame, String),
) {
  let prepend_attr_if_ok = fn(
    result: Result(#(List(Attr), xs.Event, List(xs.Event)), #(Blame, String)),
    attr: Attr,
  ) {
    case result {
      Error(e) -> Error(e)
      Ok(#(attrs, end, rest)) -> Ok(#([attr, ..attrs], end, rest))
    }
  }

  use #(first, rest) <- on_continuation(
    case tri_way(rest) {
      TagEnd(tag_end, rest) ->
        Return(Ok(#([], tag_end, rest)))

      NoMoreEvents ->
        Return(Error(#(tag_start.blame, "ran out of events while waiting for end of tag")))

      SomethingElse(first, rest, _) ->
        Continuation(#(first, rest))
    }
  )

  use #(key_blame, key_name) <- on.ok(
    case first {
      xs.Key(b, k) -> Ok(#(b, k))
      _ -> Error(#(
        first.blame,
        "expecting tag end or valid key after tag name; tag_start" <> xs.event_digest(tag_start) <> "; had " <> xs.event_digest(first) <> " instead",
      ))
    }
  )

  // we accept a solitary key, or solitary key with '='
  // (e.g. 'async' or 'async=') as an assignment to the
  // empty string; but if the '=' is not followed by a 
  // space or by tag end then whatever follows the '='
  // will only be considered as a possible attr val,
  // and not as a possible next key (while considering the
  // current assignment as empty)
  let proto = Attr(key_blame, key_name, "")

  use #(second, rest) <- on_continuation(
    case tri_way(rest) {
      TagEnd(tag_end, rest) ->
        Return(Ok(#([proto], tag_end, rest)))

      NoMoreEvents ->
        Return(Error(#(tag_start.blame, "ran out of events while waiting for end of tag")))

      SomethingElse(second, rest, _) ->
        Continuation(#(second, rest))
    }
  )

  use _ <- on_continuation(
    case second {
      xs.Assignment(_) -> Continuation(Nil)
      _ -> Return(
        // if the key wasn't followed by '=' then it can only
        // be followed by spaces or by tag end, and either way
        // (tag end or spaces and no '=') it is fine for us to
        // keep attrs parsing from scratch:
        get_attrs_and_tag_end(tag_start, [second, ..rest])
        |> prepend_attr_if_ok(proto)
      )
    }
  )

  // 'key=' or 'key  ='

  use #(third, rest, had_spaces) <- on_continuation(
    case tri_way(rest) {
      TagEnd(tag_end, rest) ->
        Return(Ok(#([proto], tag_end, rest)))

      NoMoreEvents ->
        Return(Error(#(tag_start.blame, "ran out of events while waiting for end of tag")))

      SomethingElse(third, rest, had_spaces) ->
        Continuation(#(third, rest, had_spaces))
    }
  )

  case third {
    xs.ValueDoubleQuoted(_, val) | xs.ValueSingleQuoted(_, val) -> {
      get_attrs_and_tag_end(tag_start, rest)
      |> prepend_attr_if_ok(Attr(..proto, val: val))
    }

    xs.ValueMalformed(blame, val) ->
      Error(#(blame, "malformed attr val: " <> val))

    _ -> {
      case get_attrs_and_tag_end(tag_start, rest) {
        Error(e) -> Error(e)
        Ok(#(attrs, end, rest)) -> case had_spaces, attrs {
          False, [some, ..] ->
            Error(#(some.blame, "expecting attr val after '='"))
          _, _ ->
            Ok(#([proto, ..attrs], end, rest))
        }
      }
    }
  }
}

fn reach_end_of_comments(
  comment_start: xs.Event,
  rest: List(xs.Event),
) -> Result(#(List(xs.Event), List(xs.Event)), #(Blame, String)) {
  case rest {
    [xs.CommentEndSequence(_), ..rest] -> {
      Ok(#([], rest))
    }
    [xs.CommentContents(_, _) as first, ..rest] -> {
      use #(before, after) <- on.ok(reach_end_of_comments(comment_start, rest))
      Ok(#([first, ..before], after))
    }
    [xs.Newline(_), ..rest] -> {
      // just ignore it:
      reach_end_of_comments(comment_start, rest)
    }
    [] -> {
      Error(#(comment_start.blame, "unclosed comment"))
    }
    [some, ..] -> {
      let msg = "non-comment Event after comment start; start: " <> bl.blame_digest(comment_start.blame) <> "; Event: " <> xs.event_digest(some)
      panic as msg
    }
  } 
}

fn xml_streaming_get_next_logical_unit(
  events: List(xs.Event)
) -> Result(#(XMLStreamingParserLogicalUnit, List(xs.Event)), #(Blame, String)) {
  let assert [first, ..rest] = events

  // io.println("first: " <> xs.event_digest(first))

  case first {
    // XMLStreamingParserText
    xs.Text(_, _) | xs.Newline(_) -> {
      let #(guys, remaining) = take_while_text_or_newline(events)
      let assert [last, ..] = guys
      let guys = case last {
        xs.Newline(b) -> [xs.Text(b, ""), ..guys]
        _ -> guys
      }
      let guys = guys |> list.reverse
      let guys = case first {
        xs.Newline(b) -> [xs.Text(b, ""), ..guys]
        _ -> guys
      }
      let lines = list.map(
        guys,
        fn(x) { case x {
          xs.Newline(_) -> None
          xs.Text(b, c) -> Some(Line(b, c))
          _ -> panic
        }}
      )
      |> option.values
      Ok(#(XMLStreamingParserText(lines), remaining))
    }

    // construction of: 
    //   - XMLStreamingParserOpeningTag
    //   - XMLStreamingParserSelfClosingTag
    xs.TagStartOrdinary(blame, tag) -> {
      use #(attrs, end, remaining) <- on.ok(get_attrs_and_tag_end(first, rest))
      case end {
        xs.TagEndOrdinary(_) ->
          Ok(#(XMLStreamingParserOpeningTag(blame, tag, attrs), remaining))
        xs.TagEndSelfClosing(_) ->
          Ok(#(XMLStreamingParserSelfClosingTag(blame, tag, attrs), remaining))
        xs.TagEndXMLVersion(b) ->
          Error(#(b, "unexpected '?>' tag ending"))
        _ -> panic
      }
    }

    // construction of XMLStreamingParserXMLVersion
    xs.TagStartXMLVersion(blame, tag) -> {
      assert tag == "xml" || tag == "XML"
      use #(attrs, end, remaining) <- on.ok(get_attrs_and_tag_end(first, rest))
      case end {
        xs.TagEndXMLVersion(_) -> 
          Ok(#(XMLStreamingParserXMLVersion(blame, tag, attrs), remaining))
        xs.TagEndOrdinary(b) -> 
          Error(#(b, "expecting '?>' tag ending"))
        xs.TagEndSelfClosing(b) ->
          Error(#(b, "expecting '?>' tag ending"))
        _ -> panic
      }
    }

    // construction of XMLStreamingParserDoctype
    xs.TagStartDoctype(blame, tag) -> {
      use #(attrs, end, remaining) <- on.ok(get_attrs_and_tag_end(first, rest))
      case end {
        xs.TagEndOrdinary(_) ->
          Ok(#(XMLStreamingParserDoctype(blame, tag, attrs, False), remaining))
        xs.TagEndSelfClosing(_) ->
          Ok(#(XMLStreamingParserDoctype(blame, tag, attrs, True), remaining))
        xs.TagEndXMLVersion(b) ->
          Error(#(b, "unexpected '?>' tag ending"))
        _ -> panic
      }
    }

    // construction of XMLStreamingParserClosingTag
    xs.TagStartClosing(blame, tag) -> {
      use #(attrs, end, remaining) <- on.ok(get_attrs_and_tag_end(first, rest))
      use <- on.nonempty_empty(
        attrs,
        fn(_, _) { Error(#(blame, "attrs in closing tag")) }
      )
      case end {
        xs.TagEndOrdinary(_) ->
          Ok(#(XMLStreamingParserClosingTag(blame, tag), remaining))
        xs.TagEndSelfClosing(b) ->
          Error(#(b, "unexpected '/>' in closing tag"))
        xs.TagEndXMLVersion(b) ->
          Error(#(b, "unexpected '?>' in closing tag"))
        _ -> panic
      }
    }

    // construction of XMLS
    xs.CommentStartSequence(_) -> {
      use #(events, remaining) <- on.ok(reach_end_of_comments(first, rest))
      let lines = list.map(events, fn(e) {
        let assert xs.CommentContents(b, l) = e
        Line(b, l)
      })
      Ok(#(XMLStreamingParserComment(lines), remaining))
    }

    // ...this completes everything we can construct!
    // ...everything else is out of place!

    _ -> {
      let msg = "inner tag content (?) when ostensibly out-of-tag: " <> ins(first)
      panic as msg
    }
  }
}

fn xml_streaming_logical_units_acc(
  remaining: List(xs.Event),
  acc: List(XMLStreamingParserLogicalUnit),
) -> Result(List(XMLStreamingParserLogicalUnit), #(Blame, String)) {
  case remaining {
    [] -> acc |> list.reverse |> Ok
    _ -> case xml_streaming_get_next_logical_unit(remaining) {
      Error(error) -> Error(error)
      Ok(#(unit, remaining)) ->
        xml_streaming_logical_units_acc(
          remaining,
          [unit, ..acc],
        )
    }
  }
}

pub fn xml_streaming_logical_units(
  events: List(xs.Event)
) -> Result(List(XMLStreamingParserLogicalUnit), #(Blame, String)) {
  xml_streaming_logical_units_acc(events, [])
}

fn list_of_digest(
  l: List(a),
  d: fn(a) -> String
) -> String {
  "[" <> { list.map(l, d) |> string.join(", ") } <> "]"
}

fn attr_digest(
  attr: Attr
) -> String {
  attr.key <> "=" <> attr.val
}

fn attrs_digest(
  attrs: List(Attr)
) -> String {
  list_of_digest(attrs, attr_digest)
}

pub fn lines_digest(
  lines: List(Line)
) -> String {
  list_of_digest(lines, fn(l) { ins(l.content) })
}

pub fn unit_digest(
  unit: XMLStreamingParserLogicalUnit
) -> String {
  case unit {
    XMLStreamingParserText(lines) ->
      "Text(" <> lines_digest(lines) <> ")"

    XMLStreamingParserOpeningTag(_, tag, attrs) ->
      "OpeningTag(" <> tag <> ", " <> attrs_digest(attrs) <> ")"

    XMLStreamingParserSelfClosingTag(_, tag, attrs) ->
      "SelfClosingTag(" <> tag <> ", " <> attrs_digest(attrs) <> ")"

    XMLStreamingParserXMLVersion(_, tag, attrs) ->
      "XMLVersion(" <> tag <> ", " <> attrs_digest(attrs) <> ")"

    XMLStreamingParserDoctype(_, tag, attrs, _) ->
      "Doctype(" <> tag <> ", " <> attrs_digest(attrs) <> ")"

    XMLStreamingParserClosingTag(_, tag) ->
      "ClosingTag(" <> tag <> ")"

    XMLStreamingParserComment(lines) ->
      "Comment(" <> lines_digest(lines) <> ")"
  }
}

pub fn units_digest(
  units: List(XMLStreamingParserLogicalUnit),
) -> String {
  list_of_digest(units, unit_digest)
}

fn v_digest(
  node: VXML
) -> String {
  let assert V(bl, tag, attrs, children) = node
  "V(" <>
  { bl.blame_digest(bl) } <>
  ", " <> tag <>
  ", " <> attrs_digest(attrs) <>
  ", " <> "[" <>
  case children {
    [_] -> "1 child]"
    _ -> ins(list.length(children)) <> " children]"
  }
  <> ")"
}

fn vxmls_from_streaming_logical_units_acc(
  units: List(XMLStreamingParserLogicalUnit),
  stack: List(VXML),
  previously_completed: List(VXML),
  filter_out_doctype_nodes: Bool,
  filter_out_root_level_text: Bool,
) -> Result(List(VXML), #(Blame, String)) {
  case units {
    [] -> {
      case stack {
        [] -> Ok(previously_completed |> list.reverse)
        [last, ..] -> {
          let assert V(blame, tag, _, _) = last
          list.each(
            stack,
            fn(s) {
              io.println(v_digest(s))
            }
          )
          Error(#(blame, "unclosed '" <> tag <> "' at end of document"))
        }
      }
    }

    [first, ..rest] -> {
      case first {
        XMLStreamingParserDoctype(b, tag, attrs, _) -> {
          let v = V(b, tag, attrs, [])
          case stack {
            [] -> vxmls_from_streaming_logical_units_acc(
              rest,
              [],
              case filter_out_doctype_nodes {
                True -> previously_completed
                False -> [v, ..previously_completed]
              },
              filter_out_doctype_nodes,
              filter_out_root_level_text,
            )
            _ -> Error(#(b, "found !DOCTYPE node at non-root level"))
          }
        }

        XMLStreamingParserXMLVersion(b, tag, attrs) -> {
          let v = V(b, tag, attrs, [])
          case stack {
            [] -> vxmls_from_streaming_logical_units_acc(
              rest,
              [],
              case filter_out_doctype_nodes {
                True -> previously_completed
                False -> [v, ..previously_completed]
              },
              filter_out_doctype_nodes,
              filter_out_root_level_text,
            )
            _ -> Error(#(b, "found XML version-node at non-root level"))
          }
        }

        XMLStreamingParserOpeningTag(b, tag, attrs) -> {
          let v = V(b, tag, attrs, [])
          vxmls_from_streaming_logical_units_acc(
            rest,
            [v, ..stack],
            previously_completed,
            filter_out_doctype_nodes,
            filter_out_root_level_text,
          )
        }

        XMLStreamingParserText(lines) -> {
          let assert [first_line, ..] = lines
          let t = T(first_line.blame, lines)
          let #(stack, previously_completed) = case stack {
            [last, ..others] -> {
              let assert V(_, _, _, _) = last
              let last = V(..last, children: [t, ..last.children])
              #([last, ..others], previously_completed)
            }
            _ -> case filter_out_root_level_text {
              True -> #(stack, previously_completed)
              False -> #(stack, [t, ..previously_completed])
            }
          }
          vxmls_from_streaming_logical_units_acc(
            rest,
            stack,
            previously_completed,
            filter_out_doctype_nodes,
            filter_out_root_level_text,
          )
        }

        XMLStreamingParserComment(_) -> {
          vxmls_from_streaming_logical_units_acc(
            rest,
            stack,
            previously_completed,
            filter_out_doctype_nodes,
            filter_out_root_level_text,
          )
        }

        XMLStreamingParserClosingTag(b, tag) -> {
          case stack {
            [] -> Error(#(b, "closing '</" <> tag <> ">' on empty stack"))
            [last, ..others] -> {
              let assert V(_, last_tag, _, _) = last
              case last_tag == tag {
                False -> Error(#(b, "expected closing '" <> last_tag <> "' tag, found '" <> tag <> "' instead"))
                True -> {
                  let last = V(
                    ..last,
                    children: last.children |> list.reverse,
                  )
                  case others {
                    [] -> vxmls_from_streaming_logical_units_acc(
                      rest,
                      [],
                      [last, ..previously_completed],
                      filter_out_doctype_nodes,
                      filter_out_root_level_text,
                    )
                    [parent, ..older] -> {
                      let assert V(_, _, _, _) = parent
                      let parent = V(..parent, children: [last, ..parent.children])
                      vxmls_from_streaming_logical_units_acc(
                        rest,
                        [parent, ..older],
                        [],
                        filter_out_doctype_nodes,
                        filter_out_root_level_text,
                      )
                    }
                  }
                }
              }
            }
          }
        }

        XMLStreamingParserSelfClosingTag(b, tag, attrs) -> {
          let v = V(b, tag, attrs, [])
          case stack {
            [last, ..others] -> {
              let assert V(_, _, _, _) = last
              let last = V(..last, children: [v, ..last.children])
              vxmls_from_streaming_logical_units_acc(
                rest,
                [last, ..others],
                previously_completed,
                filter_out_doctype_nodes,
                filter_out_root_level_text,
              )
            }
            [] -> {
              vxmls_from_streaming_logical_units_acc(
                rest,
                [],
                [v, ..previously_completed],
                filter_out_doctype_nodes,
                filter_out_root_level_text,
              )
            }
          }
        }
      }
    }
  }
}

fn vxmls_from_streaming_logical_units(
  units: List(XMLStreamingParserLogicalUnit),
  filter_out_doctype_nodes: Bool,
  filter_out_root_level_text: Bool,
) -> Result(List(VXML), #(Blame, String)) {
  vxmls_from_streaming_logical_units_acc(
    units,
    [],
    [],
    filter_out_doctype_nodes,
    filter_out_root_level_text,
  )
}

pub fn vxml_from_streaming_logical_units(
  units: List(XMLStreamingParserLogicalUnit)
) -> Result(VXML, #(Blame, String)) {
  use vxmls <- on.ok(vxmls_from_streaming_logical_units(units, True, True))
  case vxmls {
    [] -> Error(#(bl.no_blame, "empty document (?)"))
    [one] -> Ok(one)
    [_, second, ..] -> {
      Error(#(second.blame, "found >1 root-level nodes"))
    }
  }
}

pub fn streaming_based_xml_parser(
  lines: List(InputLine),
) -> Result(VXML, #(Blame, String)) {
  lines
  |> xs.input_lines_streamer
  |> xml_streaming_logical_units
  |> on.ok(vxml_from_streaming_logical_units)
}

pub fn streaming_based_xml_parser_string_version(
  content: String,
  filename: String,
) -> Result(VXML, #(Blame, String)) {
  content
  |> io_l.string_to_input_lines(filename, 0)
  |> streaming_based_xml_parser
}
