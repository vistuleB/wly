# VXML

VXML stands for "Vanilla XML". It is a datatype representing a small subset of
XML.

VXML keeps only the parts that people usually associate with "XML" in a
document: nested nodes with tags and attributes, plus terminal text nodes. On
the other hand, VXML deliberately omits XML declarations, CDATA, processing
instructions, namespaces, entity rules, and other ancillary XML features that
make tree transformation code harder.

VXML's main intended use is to operate as a neutral intermediate representation
within document-to-document pipelines. A parser can convert an input document
state into VXML, a pipeline can transform the tree, and an emitter can serialize
the result to HTML, XML-like text, JSX, or another target. VXML also comes with
its own indentation-based serialization format for pretty-printing, debugging,
and fixtures.

The current content of the package is:

- a compact `VXML` tree type with recursive element nodes and terminal text nodes
- source provenance and tracking through the `Blame` type
- `InputLine`/`OutputLine` types that attach Blame to source lines before parsing and preserve Blame on target lines after emitting, before final serialization
- serializers for HTML-, XML-, and JSX-like output, as well as VXML itself
- parsers for serialized VXML, XML, and forgiving HTML
- a lower-level XML tokenizer for building bespoke XML-, SVG-, or HTML-to-VXML parsers

## Data Model

The core type has two node variants:

```gleam
pub type VXML {
  V(blame: Blame, tag: String, attrs: List(Attr), children: List(VXML))
  T(blame: Blame, lines: List(Line))
}
```

- `V` is an element node: tag, attributes, and children.
- `T` is a text node: one or more source lines.
- `Attr` and `Line` also carry `Blame`.

The tree is semantics-agnostic. Tags and attributes are names, not behaviors.

## VXML Text Format

VXML includes a compact text format used for round-tripping, tests, and debug
output. Its serialization is indentation-based and canonical: each VXML tree has
one VXML text serialization.

A caret-like marker opens a node, attributes appear underneath the tag, and
quoted lines form text nodes:

```vxml
<> Article
  id=intro
  <> Title
    <>
      'A small example'
  <> Paragraph
    <>
      'VXML keeps text as text.'
      'Multiple lines stay visible.'
```

Each line of text appears as a visible quoted line, making newline placement and
whitespace easy to spot by human inspection.

Some serialization rules:

- attribute keys should be nonempty; attribute values are not quoted, follow the
  `=` directly, and may be arbitrary newline-free strings
- text nodes serialize as tag-free nodes with single-quoted lines; the text
  content of a line is the part between the first single quote and the last
  single quote, so intermediate single quotes do not need to be escaped
- a serialized text line that does not start and end with a single quote is an
  error
- indentation is fixed at two spaces, matching Gleam indentation and allowing
  VXML to be included as block strings in Gleam source

Parse it with:

```gleam
let assert Ok([tree]) =
  vxml.parse_string(source, "example.vxml", True)
```

Serialize it with:

```gleam
let text = vxml.vxml_to_string(tree)
```

## HTML and JSX Output

Use the HTML helpers when a VXML tree directly represents HTML elements:

```gleam
let lines = vxml.vxml_to_html_output_lines(tree, 0, 2)
```

The HTML serializer escapes non-entity ampersands in text. It treats common
inline tags as sticky when laying out output, so inline content is not forced
onto separate lines unless the tree requires it.

JSX-like output is available through:

```gleam
let lines = vxml.vxml_to_jsx_output_lines(tree, 0, 2)
let source = vxml.vxml_to_jsx(tree, 0, 2)
```

## Parsing XML and HTML

For XML-like input, use the streaming parser:

```gleam
let input_lines = io_lines.string_to_input_lines(source, "example.xml", 0)
let result = vxml.streaming_based_xml_parser(input_lines)
```

For HTML-ish input, use:

```gleam
let result = vxml.xmlm_based_html_parser(source, "example.html")
```

The HTML parser runs `xml_parser_html_repair` before parsing. That repair step:

- expands common boolean attributes, such as `disabled`
- escapes ampersands that are not already HTML entities
- closes HTML void tags, such as `img`, `br`, and `meta`
- removes attributes from malformed closing tags

The individual repair helpers are public so callers can apply only the repair
steps they want.

## Blame

Every node, attribute, and line carries a `Blame` value. Blame records where a
piece of data came from, or which later transformation introduced it.

```gleam
pub type Blame {
  Src(comments, path, line_no, char_no, cursor)
  Des(comments, name, line_no)
  Ext(comments, name)
  NoBlame(comments)
}
```

`SourceCursor` controls whether source positions can move when text is sliced:

- `Movable` source positions advance with text manipulation.
- `Anchored` source positions stay fixed.

This is useful for parser and transformation pipelines that need diagnostics or
source maps after several tree rewrites.

`Des` and `Ext` can be used for code-attributed blame, respectively from inside
a transformation pipeline and from outside it, such as an emitter step.

## Modules

- `vxml`: core tree types, validation, VXML parsing, HTML/JSX serialization,
  XML/HTML parsing, and HTML repair helpers
- `blame`: provenance data and formatting utilities
- `io_lines`: input/output line types and conversion helpers
- `xml_streamer`: advanced XML token stream API used by the streaming parser

Most users should start with `vxml`, `blame`, and `io_lines`. Use
`xml_streamer` when token-level XML processing is needed.

## Tests

Run the package tests from this directory:

```sh
gleam test
```
