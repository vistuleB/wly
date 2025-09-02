import gleam/int
import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/regexp
import gleam/result
import gleam/string.{inspect as ins}
import blame.{type Blame, Src, prepend_comment as pc} as bl
import io_lines.{type InputLine, InputLine, type OutputLine, OutputLine} as io_l
import simplifile
import xmlm
import on

// ************************************************************
// Attribute, TextLine, VXML (pretend 'blame' does not exist -> makes it more readable)
// ************************************************************

pub type Attribute {
  Attribute(blame: Blame, key: String, value: String)
}

pub type TextLine {
  TextLine(blame: Blame, content: String)
}

pub type VXML {
  V(blame: Blame, tag: String, attributes: List(Attribute), children: List(VXML))
  T(blame: Blame, lines: List(TextLine))
}

// ************************************************************
// more public types
// ************************************************************

pub type VXMLParseError {
  VXMLParseErrorEmptyTag(Blame)
  VXMLParseErrorIllegalTagCharacter(Blame, String, String)
  VXMLParseErrorIllegalAttributeKeyCharacter(Blame, String, String)
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
const attribute_key_illegal_characters = [".", ";", "\"", " "]

type FileHead =
  List(InputLine)

type TentativeTagName =
  Result(String, BadTagName)

type BadAttributeKey {
  IllegalAttributeKeyCharacter(String, String)
}

type TentativeAttributeKey =
  Result(String, BadAttributeKey)

type TentativeAttribute {
  TentativeAttribute(
    blame: Blame,
    key: TentativeAttributeKey,
    value: String,
  )
}

type NonemptySuffixDiagnostic {
  EmptyCaret
  TaggedCaret(tag: String)
  DoubleQuoted(with_double_quotes: String)
  Other(String)
}

type TentativeVXML {
  TentativeT(blame: Blame, lines: List(TextLine))
  TentativeV(
    blame: Blame,
    tag: TentativeTagName,
    attributes: List(TentativeAttribute),
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

fn tentative_attribute(
  blame: Blame,
  pair: #(String, String),
) -> TentativeAttribute {
  let #(key, value) = pair
  assert !string.is_empty(key)
  let bad_character = contains_one_of(key, attribute_key_illegal_characters)

  case bad_character == "" {
    True -> TentativeAttribute(blame: blame, key: Ok(key), value: value)

    False ->
      TentativeAttribute(
        blame: blame,
        key: Error(IllegalAttributeKeyCharacter(key, bad_character)),
        value: value,
      )
  }
}

fn fast_forward_past_attribute_lines_at_indent(
  indent: Int,
  head: FileHead,
) -> #(List(TentativeAttribute), FileHead) {
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
                  let tentative_attribute_pair =
                    suffix
                    |> string.split_once("=")
                    |> result.unwrap(#(suffix, ""))
                    |> tentative_attribute(blame, _)

                  let #(more_attribute_pairs, head_after_attributes) =
                    fast_forward_past_attribute_lines_at_indent(
                      indent,
                      move_forward(head),
                    )

                  #(
                    [tentative_attribute_pair, ..more_attribute_pairs],
                    head_after_attributes,
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
) -> #(List(TextLine), FileHead) {
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
                    TextLine(blame, strip_quotes(string.trim(suffix)))

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
                      let #(tentative_attributes, head_after_attributes) =
                        fast_forward_past_attribute_lines_at_indent(
                          indent + vxml_indent,
                          move_forward(head),
                        )

                      let #(children, remaining_after_children) =
                        tentative_parse_at_indent(
                          indent + vxml_indent,
                          head_after_attributes,
                        )

                      let tentative_tag =
                        TentativeV(
                          blame: blame,
                          tag: validate_tag(string.trim(annotation)),
                          attributes: tentative_attributes,
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

fn tentative_attribute_to_attribute(
  t: TentativeAttribute,
) -> Result(Attribute, VXMLParseError) {
  case t.key {
    Ok(key) -> Ok(Attribute(blame: t.blame, key: key, value: t.value))

    Error(IllegalAttributeKeyCharacter(original_would_be_key, bad_char)) ->
      Error(VXMLParseErrorIllegalAttributeKeyCharacter(
        t.blame,
        original_would_be_key,
        bad_char,
      ))
  }
}

fn tentative_attributes_to_attributes(
  attrs: List(TentativeAttribute),
) -> Result(List(Attribute), VXMLParseError) {
  case attrs {
    [] -> Ok([])
    [first, ..rest] ->
      case tentative_attribute_to_attribute(first) {
        Error(error) -> Error(error)
        Ok(attribute) ->
          case tentative_attributes_to_attributes(rest) {
            Ok(attributes) -> Ok([attribute, ..attributes])

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

    TentativeV(blame, tentative_name, tentative_attributes, tentative_children) ->
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
            tentative_attributes_to_attributes(
              tentative_attributes,
            )
          {
            Error(error) -> Error(error)

            Ok(attributes) ->
              case parse_from_tentatives(tentative_children) {
                Error(error) -> Error(error)

                Ok(children) ->
                  Ok(V(
                    blame: blame,
                    tag: name,
                    attributes: attributes,
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
    True -> echo_tentatives(parsed, "tentative_parsed")
    False -> parsed
  }
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
      tentative_attributes,
      children,
    ) -> {
      [
        OutputLine(blame, indentation, "<> " <> ins(tag_result)),
        ..list.flatten([
          list.map(tentative_attributes, fn(tentative_attribute) {
            OutputLine(
              tentative_attribute.blame,
              indentation + vxml_indent,
              ins(tentative_attribute.key)
                <> " "
                <> tentative_attribute.value,
            )
          }),
          tentatives_to_output_lines_internal(children, indentation + vxml_indent),
        ])
      ]
    }

    TentativeV(blame, Error(err), tentative_attributes, children) -> {
      [
        OutputLine(
          blame |> pc("ERROR BadTagName"),
          indentation,
          "<> " <> ins(err),
        ),
        ..list.flatten([
          list.map(tentative_attributes, fn(tentative_attribute) {
            OutputLine(
              tentative_attribute.blame,
              indentation + vxml_indent,
              ins(tentative_attribute.key)
                <> " "
                <> tentative_attribute.value,
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

fn echo_tentatives(tentatives: List(TentativeVXML), banner: String) -> List(TentativeVXML) {
  tentatives
  |> tentatives_to_output_lines_internal(0)
  |> io_l.echo_output_lines(banner)
  tentatives
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
          TextLine(
            line.blame
              |> pc("T > TextLine(" <> ins(i + 1) <> ")"),
            line.content,
          )
        }),
      )
    }
    V(blame, tag, attributes, children) -> {
      V(
        blame |> pc("V"),
        tag,
        list.index_map(attributes, fn(attribute, i) {
          Attribute(
            attribute.blame |> pc("Attribute(" <> ins(i + 1) <> ")"),
            attribute.key,
            attribute.value,
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

    V(blame, tag, attributes, children) -> {
      [
        OutputLine(blame, indentation, "<> " <> tag),
        ..list.append(
          list.map(attributes, fn(attribute) {
            OutputLine(
              attribute.blame,
              indentation + vxml_indent,
              attribute.key <> "=" <> attribute.value,
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

pub fn echo_vxml(vxml: VXML, banner: String) -> VXML {
  vxml
  |> annotate_blames
  |> vxml_to_output_lines
  |> io_l.echo_output_lines(banner)
  vxml
}

pub fn echo_vxmls(vxmls: List(VXML), banner: String) -> List(VXML) {
  vxmls
  |> list.index_map(fn(vxml, i) {echo_vxml(vxml, banner <> "-" <> ins(i + 1))})
  vxmls
}

pub fn echo_vxmls_with_root(vxmls: List(VXML), tag: String, banner: String) -> List(VXML) {
  echo_vxml(V(bl.no_blame, tag, [], vxmls), banner)
  vxmls
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
  attribute: Attribute,
  ampersand_replacer: regexp.Regexp,
) -> String {
  let value = string.trim(attribute.value) |> jsx_string_processor(ampersand_replacer)
  case value == "false" || value == "true" || result.is_ok(int.parse(value)) {
    True -> attribute.key <> "={" <> value <> "}"
    False -> attribute.key <> "=\"" <> value <> "\""
  }
}

fn jsx_attribute_output_line(
  attribute: Attribute,
  indent: Int,
  ampersand_replacer: regexp.Regexp,
) -> OutputLine {
  OutputLine(
    blame: attribute.blame,
    indent: indent,
    suffix: jsx_key_val(attribute, ampersand_replacer)
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
  attributes: List(Attribute),
  ampersand_replacer: regexp.Regexp,
) -> List(OutputLine) {
  case attributes {
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
        attributes |> list.map(jsx_attribute_output_line(_, indent, ampersand_replacer)),
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

    V(blame, tag, attributes, children) -> {
      case list.is_empty(children) {
        False ->
          [
            jsx_tag_open_output_lines(blame, tag, indent, ">", attributes, ampersand_replacer),
            children
            |> list.map(vxml_to_jsx_output_lines_internal(_, indent + 2, ampersand_replacer))
            |> list.flatten,
            jsx_tag_close_output_lines(blame, tag, indent),
          ]
          |> list.flatten

        True ->
          jsx_tag_open_output_lines(blame, tag, indent, " />", attributes, ampersand_replacer)
      }
    }
  }
}

// ************************************************************
// VXML -> jsx blamed lines
// ************************************************************

pub fn vxml_to_jsx_output_lines(vxml: VXML, indent: Int) -> List(OutputLine) {
  // a regex that matches ampersands that appear outside of html entities:
  let assert Ok(ampersand_replacer) = regexp.from_string("&(?!(?:[a-z]{2,6};|#\\d{2,4};))")
  vxml_to_jsx_output_lines_internal(vxml, indent, ampersand_replacer)
}

pub fn vxmls_to_jsx_output_lines(vxmls: List(VXML), indent: Int) -> List(OutputLine) {
  // a regex that matches ampersands that appear outside of html entities:
  let assert Ok(ampersand_replacer) = regexp.from_string("&(?!(?:[a-z]{2,6};|#\\d{2,4};))")
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

fn attributes_to_sticky_lines(
  attributes: List(Attribute),
  indent: Int,
  inline: Bool,
) -> List(StickyLine) {
  let space = case inline {
    True -> " "
    False -> ""
  }
  attributes
  |> list.map(fn(t) {
    StickyLine(
      blame: t.blame,
      indent: indent,
      content: space <> t.key <> "=\"" <> t.value <> "\"",
      sticky_start: inline,
      sticky_end: inline,
    )
  })
}

const sticky_tags = [
  "NumberedTitle", "a", "span", "i", "b", "strong", "em", "code", "tt", "br"
]

const self_closing_tags = ["img", "br", "hr"]

fn opening_tag_to_sticky_lines(
  t: VXML,
  indent: Int,
  spaces: Int,
  pre: Bool,
) -> List(StickyLine) {
  let assert V(blame, tag, attributes, _) = t
  let indent = case pre {
    True -> 0
    False -> indent
  }
  let sticky_outside = list.contains(sticky_tags, tag)
  let sticky_inside = list.length(attributes) <= 1
  list.flatten([
    [StickyLine(blame, indent, "<" <> tag, sticky_outside, sticky_inside)],
    attributes_to_sticky_lines(attributes, indent + spaces, sticky_inside),
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
  let assert Ok(ampersand_replacer) = regexp.from_string("&(?!(?:[a-z]{2,6};|#\\d{2,4};))")
  vxml_to_html_output_lines_internal(node, indent, spaces, ampersand_replacer)
}

pub fn vxmls_to_html_output_lines(
  vxmls: List(VXML),
  indent: Int,
  spaces: Int,
) -> List(OutputLine) {
  let assert Ok(ampersand_replacer) = regexp.from_string("&(?!(?:[a-z]{2,6};|#\\d{2,4};))")
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

pub type XMLMParseError {
  XMLMIOError(String)
  XMLMParseError(String)
}

fn xmlm_attribute_to_vxml_attributes(
  filename: String,
  line_no: Int,
  xmlm_attribute: xmlm.Attribute,
) -> Attribute {
  let blame = Src([], filename, line_no, 0)
  Attribute(blame, xmlm_attribute.name.local, xmlm_attribute.value)
}

pub fn xmlm_based_html_parser(
  content: String,
  filename: String,
) -> Result(VXML, XMLMParseError) {
  // some preliminary cleanup that avoids complaints
  // from the xmlm parser:
  let content = string.replace(content, "async ", "async=\"\"")
  let content = string.replace(content, "async\n", "async=\"\"\n")
  let content = string.replace(content, "\\,<", "\\,&lt;")
  let content = string.replace(content, " < ", " &lt; ")
  let content = string.replace(content, "\\rt{0.1}<", "\\rt{0.1}&lt;")
  let content = string.replace(content, "& ", "&amp;")
  let content = string.replace(content, "&\n", "&amp;\n")
  let content = string.replace(content, "\r\n", "\n")
  let content = string.replace(content, " &", "&amp;")
  let content = string.replace(content, "{", "&#123;")
  let content = string.replace(content, "}", "&#125;")
  let content = string.replace(content, "|", "&#124;")

  // close img tags
  let assert Ok(re) = regexp.from_string("(<img)(\\b(?![^>]*\\/\\s*>)[^>]*)(>)")
  let content =
    regexp.match_map(re, content, fn(match) {
      let regexp.Match(_, sub) = match
      let assert [_, Some(middle), _] = sub
      "<img" <> middle <> "/>"
    })

  // remove attributes in closing tags
  let assert Ok(re) = regexp.from_string("(<\\/)(\\w+)(\\s+[^>]*)(>)")
  let matches = regexp.scan(re, content)

  let content =
    list.fold(matches, content, fn(content_str, match) {
      let regexp.Match(_, sub) = match
      let assert [_, Some(tag), _, _] = sub
      regexp.replace(re, content_str, "</" <> tag <> ">")
    })

  // content
  // |> string.split("\n")
  // |> list.each(io.println)

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
  // //       fn(signal) {io.println(signal |> xmlm.signal_to_string)}
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
            |> list.map(xmlm_attribute_to_vxml_attributes(filename, 0, _)),
          children,
        )
      },
      fn(content) {
        let lines =
          content
          |> string.split("\n")
          |> list.map(fn(content) {
            TextLine(Src([], filename, 0, 0), content)
          })
        T(Src([], filename, 0, 0), lines)
      },
    )
  {
    Ok(#(_, vxml, _)) -> {
      vxml |> Ok
    }
    Error(input_error) -> {
      input_error |> ins |> XMLMParseError |> Error
    }
  }
}

// ************************************************************
// main & tests
// ************************************************************

fn test_vxml_sample() {
  let path = "test/sample.vxml"

  use vxmls <- on.error_ok(
    parse_file(path),
    fn (e) {
      case e {
        IOError(error) -> io.println("there was an IOError: " <> ins(error))
        DocumentError(error) -> io.println("there was a parsing error: " <> ins(error))
      }
    }
  )

  io.println("")
  io.println("list.length(vxmls) == " <> ins(list.length(vxmls)))
  io.println("")

  vxmls
  |> list.index_map(
    fn (vxml, i) {
      echo_vxml(vxml, "test_vxml_sample " <> ins(i + 1))
      io.println("")
    }
  )

  Nil
}

fn test_html_sample() -> Nil {
  let path = "test/sample.html"

  use content <- on.error_ok(
    simplifile.read(path),
    fn(_) { io.println("could not read file " <> path) },
  )

  use vxml <- on.error_ok(
    xmlm_based_html_parser(content, path),
    fn(e) { io.println("xmlm_based_html_parser error: " <> ins(e)) },
  )

  echo_vxml(vxml, "test_html_sample")

  vxml_to_html_output_lines(vxml, 0, 2)
  |> io_l.echo_output_lines("back to html")

  Nil
}

fn test_regex() {
  let assert Ok(a) = regexp.from_string("&(?!(?:[a-z]{2,6};|#\\d{2,4};))")
  echo regexp.replace(a, " &amp;&Gamma; ", "&amp;")
  echo regexp.replace(a, " &a#a; ", "&amp;")
}

pub fn make_linter_shut_up() {
  test_vxml_sample()
  test_html_sample()
  test_regex()
}

pub fn main() {
  // test_vxml_sample()
  test_html_sample()
  // test_regex()
}
