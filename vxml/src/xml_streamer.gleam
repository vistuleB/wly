import gleam/list
import gleam/io
import gleam/string.{inspect as ins}
import gleam/regexp
import splitter as sp
import blame.{type Blame} as bl
import io_lines.{type InputLine} as io_l
import on

const bd = bl.blame_digest

pub fn event_digest(
  e: Event
) -> String {
  case e {
    Newline(b) -> "Newline(" <> bd(b) <> ")"

    TagStartOrdinary(b, load) -> "TagStartOrdinary(" <> load <> ", " <> bd(b) <> ")"
    TagStartXMLVersion(b, load) -> "TagStartXMLVersion(" <> load <> ", " <> bd(b) <> ")"
    TagStartDoctype(b, load) -> "TagStartDoctype(" <> load <> ", " <> bd(b) <> ")"
    TagStartClosing(b, load) -> "TagStartClosing(" <> load <> ", " <> bd(b) <> ")"

    InTagWhitespace(b, load) -> "InTagWhitespace(" <> load <> ", " <> bd(b) <> ")"

    Key(b, load) -> "Key(" <> ins(load) <> ", " <> bd(b) <> ")"
    KeyMalformed(b, load) -> "KeyMalformed(" <> ins(load) <> ", " <> bd(b) <> ")"
    Assignment(b) -> "Assignment(" <> bd(b) <> ")"
    ValueDoubleQuoted(b, load) -> "ValueDoubleQuoted(" <> ins(load) <> ", " <> bd(b) <> ")"
    ValueSingleQuoted(b, load) -> "ValueSingleQuoted(" <> ins(load) <> ", " <> bd(b) <> ")"
    ValueMalformed(b, load) -> "ValueMalformed(" <> ins(load) <> ", " <> bd(b) <> ")"

    TagEndOrdinary(b) -> "TagEndOrdinary(" <> bd(b) <> ")"
    TagEndSelfClosing(b) -> "TagEndSelfClosing(" <> bd(b) <> ")"
    TagEndXMLVersion(b) -> "TagEndXMLVersion(" <> bd(b) <> ")"

    Text(b, load) -> "Text(" <> ins(load) <> ", " <> bd(b) <> ")"
    CommentContents(b, load) -> "CommentContents(" <> ins(load) <> ", " <> bd(b) <> ")"

    CommentStartSequence(b) -> "CommentStartSequence(" <> bd(b) <> ")"
    CommentEndSequence(b) -> "CommentEndSequence(" <> bd(b) <> ")"
  }
}

pub type Event {
  Newline(blame: Blame)                              // all newlines are recorded, can occur in or outside of a tag, but we don't support multi-line attributes so it will be outside of an attribute value

  TagStartOrdinary(blame: Blame, load: String)       // "<name"
  TagStartXMLVersion(blame: Blame, load: String)     // "<?xml" or "<?XML"
  TagStartDoctype(blame: Blame, load: String)        // "<!DOCTYPE " or "<!Doctype " or "<!doctype "
  TagStartClosing(blame: Blame, load: String)        // "</name"

  InTagWhitespace(blame: Blame, load: String)        // whitespace that occur outside of a tag go directly into Text

  Key(blame: Blame, load: String)        
  KeyMalformed(blame: Blame, load: String)        
  Assignment(blame: Blame)                           // "="
  ValueDoubleQuoted(blame: Blame, load: String)        
  ValueSingleQuoted(blame: Blame, load: String)        
  ValueMalformed(blame: Blame, load: String)        

  TagEndOrdinary(blame: Blame)                       // ">"
  TagEndSelfClosing(blame: Blame)                    // "/>"
  TagEndXMLVersion(blame: Blame)                     // "?>"

  Text(blame: Blame, load: String)
  CommentContents(blame: Blame, load: String)

  CommentStartSequence(blame: Blame)                 // "<!--" CommentStart sequences that occur inside of tag are considered errors and are ignored for the purpose of keeping in-tag/out-tag state
  CommentEndSequence(blame: Blame)                   // "-->"  CommentEnd sequences that occur without a matching CommentStart have no effect on state, either (of course)
}

pub fn is_tag_end_event(
  e: Event,
) -> Bool {
  case e {
    TagEndOrdinary(_) -> True
    TagEndSelfClosing(_) -> True
    TagEndXMLVersion(_) -> True
    _ -> False
  }
}

type ContentLine {
  ContentLine(blame: Blame, content: String)
}

type FileHead = List(ContentLine)

type State {
  OutsideTag
  InsideOpeningTagExpectingNextKey
  InsideOpeningTagExpectingNextAssignment
  InsideOpeningTagExpectingNextValue
  InsideClosingTag
  InsideComment
}

type TagOrNot {
  XMLDoc(String)    // String will be "?xml" or "?XML"
  Doctype(String)   // String will be "!DOCTYPE" or "!Doctype" or "!doctype"
  Ordinary(String)
  OrdinaryClosing(String)
  NoTag
  CommentStart
}

fn advance_line(
  cl: ContentLine,
  by: Int,
) -> ContentLine {
  assert by > 0
  assert string.length(cl.content) >= by
  ContentLine(
    bl.advance(cl.blame, by),
    string.drop_start(cl.content, by),
  )
}

pub fn is_ordinary_tag(input: String) -> Bool {
  let pattern = "^[a-zA-Z][a-zA-Z0-9._-]*$"
  let assert Ok(re) = regexp.from_string(pattern)
  regexp.check(re, input)
}

pub fn is_valid_key(input: String) -> Bool {
  let pattern = "^[a-zA-Z][:a-zA-Z0-9._-]*$"
  let assert Ok(re) = regexp.from_string(pattern)
  regexp.check(re, input)
}

fn check_for_tag_after_lt(
  after: String,
) -> TagOrNot {
  let s = sp.new([" ", ">", "/>", "?>"])
  let #(before, _, _) = sp.split(s, after)
  use <- on.true_false(
    before == "?xml" || before == "?XML",
    XMLDoc(before |> string.drop_start(1)),
  )
  use <- on.true_false(
    before == "!DOCTYPE" || before == "!Doctype" || before == "!doctype",
    Doctype(before |> string.drop_start(1)),
  )
  use <- on.true_false(
    is_ordinary_tag(before),
    Ordinary(before),
  )
  NoTag
}

fn check_for_tag_after_lt_closing(
  after: String,
) -> TagOrNot {
  let s = sp.new([" ", ">", "/>", "?>"])
  let #(before, _, _) = sp.split(s, after)
  use <- on.true_false(
    is_ordinary_tag(before),
    OrdinaryClosing(before),
  )
  NoTag
}

fn take_text_up_to_next_tag(
  text: String,
) -> #(String, TagOrNot) {
  use #(text, after) <- on.error_ok(
    string.split_once(text, "<"),
    fn(_) { #(text, NoTag) },
  )

  use <- on.lazy_true_false(
    string.starts_with(after, "/"),
    fn() {
      let after = string.drop_start(after, 1)
      case check_for_tag_after_lt_closing(after) {
        NoTag -> {
          let #(after_text, after_tag_or_not) = take_text_up_to_next_tag(after)
          #(text <> "</" <> after_text, after_tag_or_not)
        }
        some_tag -> {
          let assert OrdinaryClosing(_) = some_tag
          #(text, some_tag)
        }
      }
    }
  )

  use <- on.lazy_true_false(
    string.starts_with(after, "!--"),
    fn() {
      #(text, CommentStart)
    }
  )

  case check_for_tag_after_lt(after) {
    NoTag -> {
      let #(after_text, after_tag_or_not) = take_text_up_to_next_tag(after)
      #(text <> "<" <> after_text, after_tag_or_not)
    }
    some_tag -> {
      #(text, some_tag)
    }
  }
}

fn event_stream_internal(
  previous: List(Event),
  state: State,
  remaining: FileHead,
) -> List(Event) {
  // no lines left
  use first, rest <- on.lazy_empty_nonempty(
    remaining,
    fn() { previous |> list.reverse },
  )

  // no content left on line
  use <- on.lazy_true_false(
    first.content == "" || first.content == "\r",
    fn() {
      case rest {
        [] -> previous |> list.reverse
        _ -> event_stream_internal(
          [Newline(first.blame), ..previous],
          state,
          rest,
        )
      }
    },
  )

  // true_false
  use <- on.lazy_true_false(
    state == OutsideTag,
    fn() {
      let #(text, tag_or_not) = take_text_up_to_next_tag(first.content)
      let previous = case text != "" {
        True -> [Text(first.blame, text), ..previous]
        False -> previous
      }
      let end_of_text_blame = bl.advance(first.blame, text |> string.length)
      use <- on.lazy_true_false(
        tag_or_not == NoTag,
        fn() {
          assert text == first.content
          event_stream_internal(
            [Newline(end_of_text_blame), ..previous],
            OutsideTag,
            rest,
          )
        },
      )
      let #(tag_event, z, tag, new_state) = case tag_or_not {
        XMLDoc(tag) -> #(TagStartXMLVersion(end_of_text_blame, tag), "<?", tag, InsideOpeningTagExpectingNextKey)
        Doctype(tag) -> #(TagStartDoctype(end_of_text_blame, tag), "<!", tag, InsideOpeningTagExpectingNextKey)
        Ordinary(tag) -> #(TagStartOrdinary(end_of_text_blame, tag), "<", tag, InsideOpeningTagExpectingNextKey)
        OrdinaryClosing(tag) -> #(TagStartClosing(end_of_text_blame, tag), "</", tag, InsideClosingTag)
        CommentStart -> #(CommentStartSequence(end_of_text_blame), "<!--", "", InsideComment)
        _ -> panic as "should have escaped NoTag earlier"
      }
      let length = string.length(text <> z <> tag)
      case string.length(first.content) < length {
        True -> {
          io.println("first.content: %" <> first.content <> "%")
          io.println("text: %" <> text <> "%")
          io.println("z: %" <> z <> "%")
          io.println("tag: %" <> tag <> "%")
          panic
        }
        False -> Nil
      }
      event_stream_internal(
        [tag_event, ..previous],
        new_state,
        [advance_line(first, length), ..rest],
      )
    }
  )

  use <- on.lazy_true_false(
    state == InsideComment,
    fn() {
      case string.split_once(first.content, "-->") {
        Error(Nil) -> {
          event_stream_internal(
            [CommentContents(first.blame, first.content), ..previous],
            InsideComment,
            rest,
          )
        }
        Ok(#(before, _)) -> {
          case before == "" {
            True -> {
              event_stream_internal(
                [
                  CommentContents(first.blame, before),
                  ..previous,
                ],
                OutsideTag,
                [advance_line(first, 3), ..rest]
              )
            }
            False -> {
              let length = string.length(before)
              event_stream_internal(
                [
                  CommentEndSequence(bl.advance(first.blame, length)),
                  CommentContents(first.blame, before),
                  ..previous,
                ],
                OutsideTag,
                [advance_line(first, length + 3), ..rest]
              )
            }
          }
        }
      }
    }
  )

  // INSIDE TAG!

  // ...get rid of leading spaces
  let num_whitespace = string.length(first.content) - string.length(string.trim_start(first.content))
  use <- on.lazy_true_false(
    num_whitespace > 0,
    fn() {
      let whitespace = string.slice(first.content, 0, num_whitespace)
      event_stream_internal(
        [InTagWhitespace(first.blame, whitespace), ..previous],
        state,
        [advance_line(first, num_whitespace), ..rest],
      )
    }
  )

  // ...get rid of '=' sign
  use <- on.lazy_true_false(
    string.starts_with(first.content, "="),
    fn() {
      event_stream_internal(
        [Assignment(first.blame), ..previous],
        InsideOpeningTagExpectingNextValue,
        [advance_line(first, 1), ..rest],
      )
    }
  )

  // ...get rid of '"' quoted value
  use <- on.lazy_true_false(
    string.starts_with(first.content, "\""),
    fn() {
      let s = sp.new(["\"", "?>", "/>", ">"])
      let #(before, thing, _) = sp.split(s, first.content |> string.drop_start(1))
      let #(event, taken) = case thing == "\"" {
        True -> {
          let taken = "\"" <> before <> "\""
          #(ValueDoubleQuoted(first.blame, before), taken)
        }
        False -> {
          let taken = "\"" <> before
          #(ValueMalformed(first.blame, taken), taken)
        }
      }
      event_stream_internal(
        [event, ..previous],
        InsideOpeningTagExpectingNextKey,
        [advance_line(first, taken |> string.length), ..rest]
      )
    }
  )

  // ...get rid of "'" quoted value
  use <- on.lazy_true_false(
    string.starts_with(first.content, "'"),
    fn() {
      let s = sp.new(["'",  "?>", "/>", ">"])
      let #(before, thing, _) = sp.split(s, first.content |> string.drop_start(1))
      let #(event, taken) = case thing == "'" {
        True -> {
          let taken = "'" <> before <> "'"
          #(ValueSingleQuoted(first.blame, before), taken)
        }
        False -> {
          let taken = "'" <> before
          #(ValueMalformed(first.blame, taken), taken)
        }
      }
      event_stream_internal(
        [event, ..previous],
        InsideOpeningTagExpectingNextKey,
        [advance_line(first, taken |> string.length), ..rest]
      )
    }
  )

  // look for key
  let s = sp.new(["=", " ", "/>", "?>", ">"])
  let #(before, thing, _) = sp.split(s, first.content)
      
  // got something before closing:
  use <- on.lazy_true_false(
    before != "",
    fn() {
      let event = case is_valid_key(before) {
        True -> Key(first.blame, before)
        False -> KeyMalformed(first.blame, before)
      }
      event_stream_internal(
        [event, ..previous],
        InsideOpeningTagExpectingNextAssignment,
        [advance_line(first, before |> string.length), ..rest],
      )
    }
  )

  assert before == ""
  assert thing == "/>" || thing == "?>" || thing == ">"

  case thing {
    "/>" -> event_stream_internal(
      [TagEndSelfClosing(first.blame), ..previous],
      OutsideTag,
      [advance_line(first, 2), ..rest],
    )
    "?>" -> event_stream_internal(
      [TagEndXMLVersion(first.blame), ..previous],
      OutsideTag,
      [advance_line(first, 2), ..rest],
    )
    ">" -> event_stream_internal(
      [TagEndOrdinary(first.blame), ..previous],
      OutsideTag,
      [advance_line(first, 1), ..rest],
    )
    _ -> panic as "hey"
  }
}

fn input_line_to_content_line(
  line: InputLine,
) -> ContentLine {
  ContentLine(
    line.blame |> bl.advance(-line.indent),
    string.repeat(" ", line.indent) <> line.suffix,
  )
}

fn input_lines_to_content_lines(
  lines: List(InputLine)
) -> List(ContentLine) {
  list.map(lines, input_line_to_content_line)
}

pub fn pairs_streamer(
  lines: List(#(Blame, String))
) -> List(Event) {
  lines
  |> list.map(fn(x) { ContentLine(x.0, x.1) })
  |> event_stream_internal([], OutsideTag, _)
}

pub fn input_lines_streamer(
  lines: List(InputLine)
) -> List(Event) {
  lines
  |> input_lines_to_content_lines
  |> event_stream_internal([], OutsideTag, _)
}

pub fn string_streamer(
  s: String,
  filename: String,
) -> List(Event) {
  s
  |> io_l.string_to_input_lines(filename, 0)
  |> input_lines_streamer
}