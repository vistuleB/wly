# VXML

This package is the reference implementation of VXML ("Vanilla XML"): a
datatype and document format representing a simplified subset of XML for
document processing and markup-language transpilation.

From XML, VXML keeps only recursive nodes with tags and attributes, plus terminal
text nodes. It bypasses CDATA, processing instructions, namespaces, entity rules,
XML declarations, and other ancillary XML features.

VXML is intended to operate as an intermediate when converting between
different light-markup-style document formats, or when normalizing a document
within the same format. A parser can convert a source document into VXML,
a pipeline can transform the AST, and an emitter can serialize the result to
HTML, XML-like text, JSX, or another target. VXML's simple shape makes it easy
for each participating document format to define its own encoding and decoding
contracts, while keeping VXML -> VXML transforms quick to scaffold, compose, and
share atomically.

VXML comes with its own indentation-based serialization format for human
inspection and for persisting documents required by test suites. However, VXML
is typically expected to exist as data inside a running program, not as a
persistent storage format. In this sense, serialized VXML is designed to be
_unambiguous_, _simple_, and _human-readable_, but is not designed to be
_human-writable_. This gives serialized VXML a distinctive "read-only" shape.

In this package:

- lower-level payload types including `Blame` for source provenance, `Line` for
  line-by-line text, and `Attr` for key-value pairs
- the `VXML` tree type with recursive element nodes and terminal text nodes,
  built on `Blame`, `Line`, and `Attr`
- `InputLine`/`OutputLine` datatypes that allow `Blame`-aware inspection of line
  sequences before parsing and after emitting
- out-of-the-box parsers for XML-ish input, repaired HTML, and serialized VXML
  itself
- serializers for HTML-, XML-, and JSX-like output, as well as VXML itself
- an XML tokenizer for building bespoke XML-, SVG-, or HTML-to-VXML
  parsers

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

## Serialized Format

VXML includes a compact text format used for round-tripping, tests, and debug
output. Its serialization is indentation-based and canonical: each VXML tree has
one serialized VXML form.

A caret-like marker opens a node, attributes appear underneath the tag, and
quoted lines form text nodes:

```vxml
<> Article
  id=intro
  <> Title
    <>
      'A dark and stormy night'
  <> Section
    <> SectionTitle
      <>
        'Darkness descends'
    <> Paragraphs
      <>
        'This is the third text node'
        'of the tree, but the first'
        'text node with >1 lines.'
      <>
        'For VXML, this is just a'
        'second text node. A "paragraph"'
        'is not a VXML concept.'
```

Each line of text appears as a visible quoted line, making newline placement and
whitespace easy to spot by human inspection.

Rules & notes:

- attribute keys must be nonempty and directly followed by `=`; they may not contain the `=` char, or spaces
- attribute values are not quoted, should follow `=` directly, and may be arbitrary newline-free strings; the final attribute value is whitespace-trimmed by the parser
- text nodes serialize as anonymous `<>` containers with single-quoted lines;
  the text content of a line is the part between the first `'` and the last
  `'`, so intermediate single quotes do not need to be escaped
- a serialized text line that does not start and end with a single quote is an
  error
- indentation is fixed at two spaces, matching Gleam indentation and allowing
  VXML to be included as block strings in Gleam source
- text nodes must have at least 1 line, though the line can be the empty string

Relevant rules also apply to the VXML datatype itself, e.g., VXML is
considered malformed if an attribute key value is the empty string
or if a text node has an empty list of lines.

<!-- Parse serialized VXML with:

```gleam
let assert Ok([tree]) =
  vxml.parse_string(source, "example.vxml", True)
```

The final argument controls whether parsing expects a single root node. Serialize
VXML with:

```gleam
let text = vxml.vxml_to_string(tree)
``` -->

## Ingress: Parsing XML and HTML

VXML's XML ingress has two layers. Most callers should use the parser layer,
which converts source text into a VXML tree. Lower-level callers can use
`xml_streamer` directly to tokenize XML-like input before building their own
parser.

For the usual case, convert a string to `InputLine`s and pass them to
`streaming_based_xml_parser`:

```gleam
let assert Ok(vxml) =
  source
  |> io_lines.string_to_input_lines("relevant/path/to/source.xml", 0)
  |> vxml.streaming_based_xml_parser
```

For HTML-ish input, apply the HTML repair helpers first:

```gleam
let assert Ok(vxml) =
  source
  |> vxml.xml_parser_html_repair
  |> io_lines.string_to_input_lines("source.html", 0)
  |> vxml.streaming_based_xml_parser
```

The `xml_parser_html_repair` step:

- expands common boolean attributes, such as `disabled`
- escapes ampersands that are not already HTML entities
- closes HTML void tags, such as `img`, `br`, and `meta`
- removes attributes from malformed closing tags

The individual repair helpers are public so callers can apply only the repair
steps they want.

The tokenizer layer is available through `xml_streamer`. It exposes entry points
for strings, blamed string pairs, and `InputLine`s, returning XML token events
rather than VXML. Use it only when token-level XML access is needed before VXML
construction.

## HTML and JSX Output

Use the HTML helpers when a VXML tree directly represents HTML elements. The
output stays line-based until it is converted to a string or written to disk:

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

## Import Guide

- `vxml`: core tree types, validation, serialized VXML parsing,
  HTML/XML/JSX-like serialization, streaming XML parsing, and HTML repair
  helpers
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
