import blame.{type Blame, prepend_comment as pc} as bl
import io_lines.{type InputLine, InputLine, type OutputLine, OutputLine} as io_l
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/pair
import gleam/result
import gleam/regexp.{type Regexp}
import gleam/string.{inspect as ins}
import simplifile
import vxml.{type Attr, type Line, type VXML, Attr, Line, T, V}
import dirtree.{type DirTree} as dt
import splitter
import on.{Return, Continue as Stay}

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
  Comment(
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
  IndentationTooLarge(blame: Blame, line: String)
  IndentationNotMultipleOfFour(blame: Blame, line: String)
  CodeBlockInfoStartsWithSpace(blame: Blame, bad_info: String)
  CodeBlockNotClosed(blame: Blame)
  CodeBlockUnwantedAnnotationAtClose(blame: Blame, opening_blame: Blame, annotation: String)
  DuplicateIdInCodeBlockLanguageAnnotation(blame: Blame)
}

pub type AssemblyError {
  ReadFileError(String)
  ReadFileOrDirectoryError(String)
  TwoFilesSameName(String) // because we accept both .emu and .wly extensions, but we want to avoid mixing error
  NoFilesFound(String)
}

pub type AssemblyOrParseError {
  ParseError(ParseError)
  AssemblyError(AssemblyError)
}

// ************************************************************
// local types
// ************************************************************

type FileHead =
  List(InputLine)

type Encounter {
  EncounteredFileEnd
  EncounteredBlankLine(blame: Blame, indent: Int)
  EncounteredNonMod4Indent(blame: Blame, indent: Int, suffix: String)
  EncounteredHigherIndent(blame: Blame, indent: Int, suffix: String)
  EncounteredLowerIndent(blame: Blame, indent: Int, suffix: String)
  EncounteredTextLine(blame: Blame, suffix: String)
  EncounteredTagLine(blame: Blame, suffix: String)
  EncounteredCommentLine(blame: Blame, suffix: String)
  EncounteredCodeFence(blame: Blame, suffix: String)
}

fn nonempty_suffix_encounter(
  blame: Blame,
  suffix: String,
) -> Encounter {
  case suffix {
    "|>" <> _ -> EncounteredTagLine(blame, suffix)
    "!!" <> _ -> EncounteredCommentLine(blame, suffix)
    "```" <> _ -> EncounteredCodeFence(blame, suffix)
    _ -> EncounteredTextLine(blame, suffix)
  }
}

fn filehead_encounter(
  indent: Int,
  head: FileHead,
) -> #(Encounter, FileHead) {
  use first, rest <- on.lazy_empty_nonempty(
    head,
    fn() { #(EncounteredFileEnd, []) },
  )

  let InputLine(blame, first_indent, suffix) = first

  use <- on.lazy_true_false(
    suffix == "",
    fn() { #(EncounteredBlankLine(blame, first_indent), rest) },
  )

  use <- on.lazy_true_false(
    first_indent % 4 != 0,
    fn() { #(EncounteredNonMod4Indent(blame, first_indent, suffix), rest) },
  )

  use <- on.lazy_true_false(
    first_indent < indent,
    fn() { #(EncounteredLowerIndent(blame, first_indent, suffix), rest) },
  )

  use <- on.lazy_true_false(
    first_indent > indent,
    fn() { #(EncounteredHigherIndent(blame, first_indent, suffix), rest) },
  )

  let encounter = nonempty_suffix_encounter(blame, suffix)

  #(encounter, rest)
}

fn drop_text_line_escape(
  blame: Blame,
  suffix: String,
  rgxs: OurRegexes,
) -> Line {
  case regexp.check(rgxs.includes_bol_te_escape, suffix) {
    True -> Line(blame |> bl.advance(1), suffix |> string.drop_start(1))
    False -> Line(blame, suffix)
  }
}

fn parse_text_lines_at_indent(
  indent: Int,
  head: FileHead,
  rgxs: OurRegexes,
) -> Result(#(List(Line), Encounter, FileHead), ParseError) {
  let #(encounter, rest) = filehead_encounter(indent, head)

  case encounter {
    EncounteredTextLine(blame, suffix) -> {
      let line = drop_text_line_escape(blame, suffix, rgxs)
      use #(lines, encounter, rest) <- on.ok(parse_text_lines_at_indent(indent, rest, rgxs))
      Ok(#([line, ..lines], encounter, rest))
    }
    _ -> Ok(#([], encounter, rest))
  }
}

fn parse_comment_lines_at_indent(
  indent: Int,
  head: FileHead,
) -> Result(#(List(Line), Encounter, FileHead), ParseError) {
  let #(encounter, rest) = filehead_encounter(indent, head)

  case encounter {
    EncounteredCommentLine(blame, suffix) -> {
      let line = Line(blame |> bl.advance(2), suffix |> string.drop_start(2))
      use #(lines, encounter, rest) <- on.ok(parse_comment_lines_at_indent(indent, rest))
      Ok(#([line, ..lines], encounter, rest))
    }
    _ -> Ok(#([], encounter, rest))
  }
}

fn parse_attrs_at_indent(
  indent: Int,
  head: FileHead,
  rgxs: OurRegexes,
) -> Result(#(List(Attr), Encounter, FileHead), ParseError) {
  let #(encounter, rest) = filehead_encounter(indent, head)

  use #(blame, suffix) <- on.continue(
    case encounter {
      EncounteredTextLine(blame, suffix) -> Stay(#(blame, suffix))
      EncounteredCommentLine(blame, suffix) -> {
        let attr = Attr(blame, suffix, "")
        use #(attrs, encounter, rest) <- on.error_ok(
          parse_attrs_at_indent(indent, rest, rgxs),
          fn(e) { Return(Error(e)) },
        )
        Return(Ok(#([attr, ..attrs], encounter, rest)))
      }
      _ -> Return(Ok(#([], encounter, rest)))
    }
  )

  assert suffix != ""
  assert !string.starts_with(suffix, "!!")
  assert !string.starts_with(suffix, "|>")

  use #(key, val) <- on.error_ok(
    suffix |> string.split_once("="),
    fn(_) { Ok(#([], encounter, rest)) },
  )

  use <- on.lazy_true_false(
    key == "" || string.contains(key, " ") || !regexp.check(rgxs.is_valid_key, key),
    fn() { Ok(#([], encounter, rest)) },
  )

  let val = string.trim(val)
  let attr = Attr(blame, key, val)
  use #(attrs, encounter, rest) <- on.ok(parse_attrs_at_indent(indent, rest, rgxs))
  Ok(#([attr, ..attrs], encounter, rest))
}

fn parse_writerlys_at_indent_from_nonempty_suffix(
  indent: Int,
  rest: FileHead,
  rgxs: OurRegexes,
  blame: Blame,
  suffix: String,
) -> Result(#(List(Writerly), List(Writerly), Encounter, FileHead), ParseError) {
  let encounter = nonempty_suffix_encounter(blame, suffix)
  parse_writerlys_at_indent_from_encounter(indent, rest, rgxs, encounter)
}

fn parse_writerlys_at_indent_from_encounter(
  indent: Int,
  rest: FileHead,
  rgxs: OurRegexes,
  encounter: Encounter,
) -> Result(#(List(Writerly), List(Writerly), Encounter, FileHead), ParseError) {
  case encounter {
    EncounteredFileEnd -> {
      Ok(#([], [], EncounteredFileEnd, []))
    }

    EncounteredBlankLine(blame, _) -> {
      let writerly = BlankLine(blame)
      use #(s1, s2, encounter, rest) <- on.ok(parse_writerlys_at_indent(indent, rest, rgxs))
      let #(s1, s2) = case s1 {[] -> #(s1, [writerly, ..s2]) _ -> #([writerly, ..s1], s2)}
      Ok(#(s1, s2, encounter, rest))
    }

    EncounteredNonMod4Indent(blame, _, suffix) -> {
      Error(IndentationNotMultipleOfFour(blame, suffix))
    }

    EncounteredHigherIndent(blame, _, suffix) -> {
      Error(IndentationTooLarge(blame, suffix))
    }

    EncounteredLowerIndent(blame, suffix_indent, suffix) -> {
      assert suffix_indent <= indent
      assert suffix != ""
      case suffix_indent < indent {
        True -> Ok(#([], [], encounter, rest))
        False -> parse_writerlys_at_indent_from_nonempty_suffix(indent, rest, rgxs, blame, suffix)
      }
    }

    EncounteredCommentLine(blame, suffix) -> {
      let line = Line(blame |> bl.advance(2), suffix |> string.drop_start(2))
      use #(lines, encounter, rest) <- on.ok(parse_comment_lines_at_indent(indent, rest))
      let writerly = Comment(blame, [line, ..lines])
      use #(s1, s2, encounter, rest) <- on.ok(parse_writerlys_at_indent_from_encounter(indent, rest, rgxs, encounter))
      Ok(#([writerly, ..s1], s2, encounter, rest))
    }

    EncounteredTextLine(blame, suffix) -> {
      let line = drop_text_line_escape(blame, suffix, rgxs)
      use #(lines, encounter, rest) <- on.ok(parse_text_lines_at_indent(indent, rest, rgxs))
      let writerly = Blurb(blame, [line, ..lines])
      use #(s1, s2, encounter, rest) <- on.ok(parse_writerlys_at_indent_from_encounter(indent, rest, rgxs, encounter))
      Ok(#([writerly, ..s1], s2, encounter, rest))
    }

    EncounteredTagLine(blame, suffix) -> {
      let tag = suffix |> string.drop_start(2) |> string.trim
      use <- on.lazy_false_true(
        regexp.check(rgxs.is_valid_tag, tag),
        fn() { Error(BadTag(blame, tag)) }
      )
      use #(attrs, encounter, rest) <- on.ok(parse_attrs_at_indent(indent + 4, rest, rgxs))
      use #(s1, s2, encounter, rest) <- on.ok(parse_writerlys_at_indent_from_encounter(indent + 4, rest, rgxs, encounter))
      let writerly = Tag(blame, tag, attrs, s1)
      use #(s3, s4, encounter, rest) <- on.ok(parse_writerlys_at_indent_from_encounter(indent, rest, rgxs, encounter))
      let #(all_children, blanks) = case s3 {
        [] -> {
          assert s4 == []
          #([writerly], s2)
        }
        _ -> {
          #([writerly, ..list.append(s2, s3)], s4)
        }
      }
      Ok(#(all_children, blanks, encounter, rest))
    }

    EncounteredCodeFence(blame, suffix) -> {
      use attrs <- on.ok(parse_code_block_info(blame |> bl.advance(3), suffix |> string.drop_start(3), rgxs))
      use #(lines, rest) <- on.ok(parse_code_block_at_indent(indent, rest, blame, rgxs))
      let writerly = CodeBlock(blame, attrs, lines)
      use #(s1, s2, encounter, rest) <- on.ok(parse_writerlys_at_indent(indent, rest, rgxs))
      Ok(#([writerly, ..s1], s2, encounter, rest))
    }
  }
}

fn parse_code_block_at_indent(
  indent: Int,
  head: FileHead,
  initial_blame: Blame,
  rgxs: OurRegexes,
) -> Result(#(List(Line), FileHead), ParseError) {
  use first, rest <- on.lazy_empty_nonempty(
    head,
    fn() { Error(CodeBlockNotClosed(initial_blame)) }
  )

  let InputLine(blame, first_indent, suffix) = first

  use <- on.lazy_true_false(
    first_indent > indent,
    fn() {
      let spaces = string.repeat(" ", first_indent - indent)
      let content = spaces <> suffix
      let line = Line(blame |> bl.advance(indent - first_indent), content)
      use #(lines, rest) <- on.ok(parse_code_block_at_indent(indent, rest, initial_blame, rgxs))
      Ok(#([line, ..lines], rest))
    }
  )

  use <- on.lazy_true_false(
    suffix == "",
    fn() {
      let line = Line(blame, "")
      use #(lines, rest) <- on.ok(parse_code_block_at_indent(indent, rest, initial_blame, rgxs))
      Ok(#([line, ..lines], rest))
    },
  )

  use <- on.lazy_true_false(
    first_indent < indent,
    fn() { Error(CodeBlockNotClosed(initial_blame)) }
  )

  use <- on.lazy_true_false(
    suffix |> string.starts_with("```"),
    fn() {
      let suffix = suffix |> string.drop_start(3) |> string.trim_end()
      case suffix {
        "" -> Ok(#([], rest))
        _ -> Error(CodeBlockUnwantedAnnotationAtClose(blame, initial_blame, suffix))
      }
    }
  )

  let #(blame, suffix) = case regexp.check(rgxs.includes_bol_cb_escape, suffix) {
    True -> #(blame |> bl.advance(1), suffix |> string.drop_start(1))
    False -> #(blame, suffix)
  }

  let line = Line(blame, suffix)
  use #(lines, rest) <- on.ok(parse_code_block_at_indent(indent, rest, initial_blame, rgxs))
  Ok(#([line, ..lines], rest))
}

fn reassemble_code_block_info(
  attrs: List(Attr),
) -> String {
  let #(info, attrs) = list.fold(
    attrs,
    #(None, []),
    fn (acc, attr) {
      case attr.key == "info" && acc.0 == None {
        True -> #(Some(attr), acc.1)
        False -> #(acc.0, [attr, ..acc.1])
      }
    }
  )
  let escape = fn(s) {
    s
    |> string.replace("\\", "\\\\")
    |> string.replace("&", "\\&")
  }
  let keyval_maker = fn(attr: Attr) -> String {
    { attr.key <> "=" <> attr.val }
    |> escape
  }
  let keyvals =
    attrs
    |> list.reverse
    |> list.map(keyval_maker)
  let info = case info {
    None -> ""
    Some(info) -> info.val |> escape
  }
  [info, ..keyvals] |> string.join("&")
}

fn parse_code_block_info(
  blame: Blame,
  info: String,
  rgxs: OurRegexes,
) -> Result(List(Attr), ParseError) {
  let info = info |> string.trim_end()

  use <- on.lazy_true_false(
    info == "",
    fn() { Ok([]) },
  )

  use <- on.lazy_true_false(
    info |> string.starts_with(" "),
    fn() { Error(CodeBlockInfoStartsWithSpace(blame, info)) },
  )

  use <- on.lazy_false_true(
    info |> string.contains("&"),
    fn() { Ok([Attr(blame, "info", info)]) },
  )

  let pieces = regexp.split(rgxs.unescaped_ampersand, info)

  let pieces = list.map_fold(
    pieces,
    #(blame, ""),
    fn(acc, p) {
      let #(blame, last_piece) = acc
      let acc = #(blame |> bl.advance(last_piece |> string.length), p)
      #(acc, acc)
    }
  )
  |> pair.second

  let pieces = list.index_map(
    pieces,
    fn (p, i) {
      let #(blame, p) = p
      let p = case i % 3 {
        0 -> p |> string.replace("\\&", "&") |> string.replace("\\\\", "\\")
        1 -> p |> string.replace("\\\\", "\\")
        2 -> p
        _ -> panic
      }
      #(blame, p)
    }
  )

  let keyvals = list.fold(
    pieces,
    #(None, 0, []),
    fn(acc, p) {
      let #(maybe, i, so_far) = acc
      case i % 3 {
        0 -> {
          assert maybe == None
          #(Some(p), i + 1, so_far)
        }
        1 -> {
          let assert Some(#(prev_blame, prev_p)) = maybe
          let #(_, p) = p
          #(None, i + 1, [#(prev_blame, prev_p <> p), ..so_far])
        }
        2 -> {
          assert maybe == None
          #(None, i + 1, so_far)
        }
        _ -> panic
      }
    }
  )

  let keyvals = case keyvals.0 {
    None -> keyvals.2 |> list.reverse
    Some(x) -> [x, ..keyvals.2] |> list.reverse
  }

  let assert [info, ..keyvals] = keyvals
  let info = Attr(info.0, "writerly-code-block-info", info.1)

  use keyvals <- on.ok(list.try_map(
    keyvals,
    fn(kv) {
      let #(blame, kv) = kv
      let #(key, val) = 
        string.split_once(kv, "=")
        |> result.unwrap(#(kv, ""))
      let key = string.trim(key)
      let val = string.trim(val)
      case regexp.check(rgxs.is_valid_key, key) {
        False -> Error(BadKey(blame, key))
        True -> Ok(Attr(blame, key, val))
      }
    }
  ))

  let attrs = case info.val {
    "" -> keyvals
    _ -> [info, ..keyvals]
  }

  Ok(attrs)
}

fn parse_writerlys_at_indent(
  indent: Int,
  head: FileHead,
  rgxs: OurRegexes,
) -> Result(#(List(Writerly), List(Writerly), Encounter, FileHead), ParseError) {
  let #(encounter, rest) = filehead_encounter(indent, head)
  parse_writerlys_at_indent_from_encounter(indent, rest, rgxs, encounter)
}

// ************************************************************
// 'info' string HTML processing
// ************************************************************

type InfoHTMLPiece {
  Id(blame: Blame, payload: String)
  Class(blame: Blame, payload: String)
  Style(blame: Blame, payload: String)
}

fn split_while(
  s: splitter.Splitter,
  suffix: String,
  blame: Blame,
) -> #(String, List(#(Blame, String, String))) {
  let #(before, sep, after) = splitter.split(s, suffix)
  use _ <- on.continue(case sep {
    "" -> Return(#(before, []))
    _ -> Stay(Nil)
  })
  let b1 = bl.advance(blame, string.length(before))
  let b2 = bl.advance(b1, string.length(sep))
  let #(u, others) = split_while(s, after, b2)
  #(before, [#(b1, sep, u), ..others])
}

fn info_html_pieces(
  s: splitter.Splitter,
  suffix: String,
  blame: Blame,
) -> #(String, List(InfoHTMLPiece)) {
  let #(tag, pieces) = split_while(s, suffix, blame)
  let pieces = list.map(pieces, fn(p) {
    case p {
      #(b, ".", payload) -> {
        case string.contains(payload, ":") {
          True -> Style(b, payload)
          False -> Class(b, payload)
        }
      }
      #(b, "#", payload) -> Id(b, payload)
      _ -> panic
    }
  })
  #(tag, pieces)
}

pub fn expand_clode_block_info_html_shorthand(
  blame: Blame,
  info: String,
) -> Result(#(
  Option(Attr), // language
  Option(Attr), // id
  Option(Attr), // class
  Option(Attr), // style
), String) {
  assert info == string.trim(info)
  assert info != ""
  let s = splitter.new([".", "#"])
  let #(language, pieces) = info_html_pieces(s, info, blame)
  let #(ids, classes, styles) = list.fold(
    pieces,
    #([], [], []),
    fn(acc, p) {
      case p {
        Id(..) -> #([p, ..acc.0], acc.1, acc.2)
        Class(..) -> #(acc.0, [p, ..acc.1], acc.2)
        Style(..) -> #(acc.0, acc.1, [p, ..acc.2])
      }
    }
  )
  let language = case language {
    "" -> None
    _ -> Some(Attr(blame, "language", language))
  }
  use id <- on.ok(case ids {
    [] -> Ok(None)
    [one] -> Ok(Some(Attr(one.blame, "id", one.payload)))
    _ -> Error("duplicate HTML id (two '#' in 'info' string)")
  })
  let class = case classes {
    [] -> None
    [first, ..] -> {
      let val = list.map(classes, fn(d) {
        d.payload |> string.trim
      }) |> list.reverse |> string.join(" ")
      Some(Attr(first.blame, "class", val))
    }
  }
  let style = case styles {
    [] -> None
    [first, ..] -> {
      let val = list.map(styles, fn(d) {
        d.payload |> string.trim
      }) |> list.reverse |> string.join(";")
      Some(Attr(first.blame, "style", val))
    }
  }
  Ok(#(language, id, class, style))
}

// ************************************************************
// writerly parsing api (input lines)
// ************************************************************

type OurRegexes {
  OurRegexes(
    is_valid_tag: Regexp,
    is_valid_key: Regexp,
    includes_bol_te_escape: Regexp,     // te = 'text',       'includes_' = (as we parse source)
    includes_bol_cb_escape: Regexp,     // cb = 'code block', 'includes_' = (as we parse source)
    requires_bol_te_escape: Regexp,     // te = 'text',       'requires_' = (as we output source)
    requires_bol_cb_escape: Regexp,     // cb = 'code block', 'requires_' = (as we output source)
    unescaped_ampersand: Regexp,
  )
}

fn our_regexes() -> OurRegexes {
  let assert Ok(is_valid_tag) = regexp.from_string("^[a-zA-Z_\\:][-a-zA-Z0-9\\._\\:]*$")
  let assert Ok(is_valid_key) = regexp.from_string("^[a-zA-Z_][-a-zA-Z0-9\\._\\:]*$")
  let assert Ok(includes_bol_te_escape) = regexp.from_string("^\\\\+(\\s|\\t|!!|```)")
  let assert Ok(includes_bol_cb_escape) = regexp.from_string("^\\\\+(```)")
  let assert Ok(requires_bol_te_escape) = regexp.from_string("^\\\\*(\\s|\\t|!!|```)")
  let assert Ok(requires_bol_cb_escape) = regexp.from_string("^\\\\*(```)")
  let assert Ok(unescaped_ampersand) = regexp.from_string("(?<!\\\\)(\\\\\\\\)*(&)")

  OurRegexes(
    is_valid_tag,
    is_valid_key,
    includes_bol_te_escape,
    includes_bol_cb_escape,
    requires_bol_te_escape,
    requires_bol_cb_escape,
    unescaped_ampersand,
  )
}

pub fn parse_input_lines(
  lines: FileHead
) -> Result(List(Writerly), ParseError) {
  let rgxs = our_regexes()
  use #(writerlys, _, _, _) <- on.ok(parse_writerlys_at_indent(0, lines, rgxs))
  let writerlys = list.filter(writerlys, fn(writerly) { case writerly {
    BlankLine(..) -> False
    _ -> True
  }})
  Ok(writerlys)
}

// ************************************************************
// writerly parsing api (string)
// ************************************************************

pub fn parse_string(
  source: String,
  filename: String,
) -> Result(List(Writerly), ParseError) {
  source
  |> io_l.string_to_input_lines(filename, 0)
  |> parse_input_lines
}

// ************************************************************
// printing Tentative
// ************************************************************

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

// ************************************************************
// Writerly -> blamed lines internals
// ************************************************************

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
    Comment(blame, lines) ->
      Comment(
        blame |> pc("Comment"),
        list.index_map(lines, fn(line, i) {
          Line(
            line.blame
              |> pc("Comment > Line(" <> ins(i + 1) <> ")"),
            line.content,
          )
        }),
      )
    CodeBlock(blame, attrs, lines) -> {
      let info = reassemble_code_block_info(attrs)
      CodeBlock(
        blame |> pc("CodeBlock:" <> info),
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
  rgxs: OurRegexes,
) -> List(OutputLine) {
  case t {
    BlankLine(blame) -> [OutputLine(blame, 0, "")]

    Blurb(_, lines) ->
      lines
      |> add_escapes_in_lines(rgxs.requires_bol_te_escape)
      |> lines_to_output_lines(indentation)

    Comment(_, lines) ->
      lines
      |> list.map(fn(l) {Line(..l, content: "!!" <> l.content)})
      |> lines_to_output_lines(indentation)

    CodeBlock(blame, attrs, lines) -> {
      list.flatten([
        [
          OutputLine(blame, indentation, "```" <> reassemble_code_block_info(attrs)),
        ],
        lines
        |> add_escapes_in_lines(rgxs.requires_bol_cb_escape)
        |> lines_to_output_lines(indentation),
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
        |> list.map(writerly_to_output_lines_internal(_, indentation + 4, annotate_blames, rgxs))
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

// ************************************************************
// Writerly -> output lines api
// ************************************************************

pub fn writerly_to_output_lines(
  writerly: Writerly,
) -> List(OutputLine) {
  let rgxs = our_regexes()
  writerly
  |> writerly_to_output_lines_internal(0, False, rgxs)
}

pub fn writerlys_to_output_lines(
  writerlys: List(Writerly),
) -> List(OutputLine) {
  writerlys
  |> list.map(writerly_to_output_lines)
  |> list.flatten
}

// ************************************************************
// Writerly -> String api
// ************************************************************

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

// ************************************************************
// echo_writerly api
// ************************************************************

pub fn writerly_table(writerly: Writerly, banner: String, indent: Int) -> String {
  let rgxs = our_regexes()
  writerly
  |> writerly_annotate_blames
  |> writerly_to_output_lines_internal(0, True, rgxs)
  |> io_l.output_lines_table(banner, indent)
}

// ************************************************************
// Writerly -> VXML
// ************************************************************

const writerly_blank_line_vxml_tag = "WriterlyBlankLine"
const writerly_code_block_vxml_tag = "WriterlyCodeBlock"
const writerly_comment_vxml_tag = "WriterlyComment"

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
    
    Comment(blame, lines) -> 
      V(
        blame: blame,
        tag: writerly_comment_vxml_tag,
        attrs: [],
        children: [T(blame: blame, lines: lines)],
      )

    CodeBlock(blame, attrs, lines) ->
      V(
        blame: blame,
        tag: writerly_code_block_vxml_tag,
        attrs: attrs,
        children: case lines {
          [] -> []
          _ -> [T(blame: blame, lines: lines)]
        },
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

// ************************************************************
// assemble_input_lines internals
// ************************************************************

fn file_is_not_commented(path: String) -> Bool {
  !{ string.contains(path, "/#") || string.starts_with(path, "#") }
}

fn is_parent(path: String) -> Bool {
  path == "__parent.wly" || string.ends_with(path, "/__parent.wly")
}

fn file_is_selected_or_has_selected_descendant(
  path_selectors: List(String),
  path: String,
  all_paths: List(String),
) -> Bool {
  path_selectors == []
  || list.any(path_selectors, string.contains(path, _))
  || {
    is_parent(path) && {
      let prefix = path |> string.drop_end(string.length("__parent.wly"))
      list.any(
        all_paths,
        fn (x) {
          string.starts_with(x, prefix) &&
          list.any(path_selectors, string.contains(x, _))
        }
      )
    }
  }
}

fn shortname_for_blame(path: String, dirname: String) -> String {
  let length_to_drop = case string.ends_with(dirname, "/") || dirname == "" {
    True -> string.length(dirname)
    False -> string.length(dirname) + 1
  }
  string.drop_start(path, length_to_drop)
}

fn input_lines_for_file_at_depth(
  dirname: String,
  path: String,
  depth: Int,
) -> Result(List(InputLine), AssemblyError) {
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

fn path_2_dir_and_filename(path: String) -> #(String, String) {
  let reversed_path = path |> string.reverse
  let #(reversed_filename, reversed_dir) =
    reversed_path
    |> string.split_once("/")
    |> result.unwrap(#(reversed_path, ""))
  #(reversed_dir |> string.reverse, reversed_filename |> string.reverse)
}

fn dir_and_filename_2_path(p: #(String, String)) -> String {
  case p.0 {
    "" -> p.1
    _ -> p.0 <> "/" <> p.1
  }
}

fn get_dirname_and_relative_paths_of_uncommented_wly_in_dir(
  dirpath_or_filepath: String,
) -> Result(#(String, List(String)), AssemblyError) {
  use #(dirname, fullpaths_including_dirname) <- on.ok(
    case simplifile.get_files(dirpath_or_filepath) {
      Ok(files) -> {
        Ok(#(dirpath_or_filepath |> drop_slash, files))
      }
      Error(simplifile.Enotdir) -> {
        let #(dirname, filepath) = dirpath_or_filepath |> path_2_dir_and_filename
        Ok(#(dirname, [dirname <> "/" <> filepath]))
      }
      Error(error) -> Error(
        ReadFileOrDirectoryError("error accessing dirpath_or_filepath:"  <> dirpath_or_filepath  <> ", " <> ins(error))
      )
    }
  )

  assert !string.ends_with(dirname, "/")
  let dirname_length = string.length(dirname)
  let relative_filepaths =
    fullpaths_including_dirname
    |> list.filter(string.ends_with(_, ".wly"))
    |> list.filter(file_is_not_commented)
    |> list.map(fn(path) {
      let path = string.drop_start(path, dirname_length)
      assert string.starts_with(path, "/")
      string.drop_start(path, 1)
    })

  Ok(#(dirname, relative_filepaths))
}

fn filename_compare(f1: String, f2: String) {
  assert f1 != f2
  case f1 == "__parent.wly" {
    True -> order.Lt
    False -> {
      case f2 == "__parent.wly" {
        True -> order.Gt
        False -> string.compare(f1, f2)
      }
    }
  }
}

fn lexicographic_sort_but_parent_comes_first_v2(
  dirname_and_file_1: #(String, String),
  dirname_and_file_2: #(String, String),
) -> order.Order {
  let dir_order = string.compare(dirname_and_file_1.0, dirname_and_file_2.0)
  case dir_order {
    order.Eq -> filename_compare(dirname_and_file_1.1, dirname_and_file_2.1)
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

fn input_lines_for_dirtree_at_depth(
  original_dirname: String,
  path_to_tree: String,
  tree: DirTree,
  depth: Int,
) -> Result(List(InputLine), AssemblyError) {
  assert string.ends_with(path_to_tree, tree.name)
  case tree.contents {
    [] -> {
      assert string.ends_with(tree.name, ".wly")
      input_lines_for_file_at_depth(
        original_dirname,
        path_to_tree,
        depth,
      )
    }
    [first, ..rest] -> {
      // the first guy never gets indented, whether there is a parent or not!:
      use first_lines <- on.ok(
        input_lines_for_file_at_depth(original_dirname, path_to_tree <> "/" <> first.name, depth)
      )
      let added_depth = case first.name == "__parent.wly" {
        True -> 1
        False -> 0
      }
      use lines_of_rest <- on.ok(
        list.try_map(
          rest,
          fn(subtree) {
            input_lines_for_dirtree_at_depth(
              original_dirname,
              path_to_tree <> "/" <> subtree.name,
              subtree,
              depth + added_depth,
            )
          }
        )
      )
      [
        first_lines,
        ..lines_of_rest
      ]
      |> list.flatten
      |> Ok
    }
  }
}

fn drop_slash(s: String) {
  case string.ends_with(s, "/") {
    True -> string.drop_end(s, 1)
    False -> string.drop_end(s, 0)
  }
}

pub fn assemble_input_lines_advanced_mode(
  dirpath_or_filepath: String,
  path_selectors: List(String),
) -> Result(#(List(String), List(InputLine)), AssemblyError) {
  use #(dirname, paths) <- on.ok(
    get_dirname_and_relative_paths_of_uncommented_wly_in_dir(dirpath_or_filepath)
  )

  use _, _ <- on.empty_nonempty(
    paths,
    Error(NoFilesFound("no files found in: " <> dirpath_or_filepath)),
  )

  let sorted =
    paths
    |> list.map(path_2_dir_and_filename)
    |> list.sort(lexicographic_sort_but_parent_comes_first_v2)
    |> list.map(dir_and_filename_2_path)
    |> list.filter(
      // fyi the implementation of this function could be optimized
      // to take advantage of the sorted paths (but only matters if
      // path_selectors != []):
      file_is_selected_or_has_selected_descendant(path_selectors, _, paths),
    )

  use _ <- on.ok(check_no_duplicate_files(sorted))

  let tree = dt.directory_tree_from_dir_and_paths(dirname, sorted, False)

  use lines <- on.ok(
    input_lines_for_dirtree_at_depth(dirname, dirname, tree, 0)
  )

  Ok(#(tree |> dt.pretty_printer, lines))
}

// ************************************************************
// assemble_input_lines
// ************************************************************

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

fn add_escape_in_string(s: String, re: Regexp) -> String {
  case regexp.check(re, s) {
    True -> "\\" <> s
    False -> s
  }
}

fn add_escapes_in_lines(
  contents: List(Line),
  re: Regexp,
) -> List(Line) {
  list.map(contents, fn(line) {
    Line(
      line.blame,
      line.content |> add_escape_in_string(re),
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

pub fn vxml_to_writerlys(vxml: VXML) -> List(Writerly) { // it would be 'Writerly' not 'List(Writerly)' if for the fact that someone could give an empty text node
  case vxml {
    V(blame, tag, attrs, children) -> {
      case tag {
        _ if tag == writerly_blank_line_vxml_tag -> {
          assert attrs == []
          assert children == []
          [BlankLine(blame)]
        }
        _ if tag == writerly_code_block_vxml_tag -> {
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
        _ if tag == writerly_comment_vxml_tag -> {
          let assert [T(_, lines)] = children
          assert lines != []
          [Comment(blame, lines)]
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
