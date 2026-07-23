# VXML

This package is the reference implementation of VXML ("Vanilla XML"): a
datatype and document format representing a simplified subset of XML for
document processing and markup-language transpilation.

VXML keeps only recursive nodes with tags and attributes, plus text nodes.

VXML is intended to operate as an intermediate between different
light-markup-style document formats. A parser can convert a source document into
VXML, a pipeline can transform the AST, and an emitter can serialize the result
to HTML, XML-like text, JSX, or another target. VXML's deliberately simple
shape makes it easy to reason about encoding and decoding contracts.
Transforms that map VXML to VXML are easy to write and can be composed
and shared atomically.

VXML comes with its own indentation-based serialization format for human
inspection and for persisting documents required by test suites. However, VXML
is typically expected to exist as data inside a running program, not as a
persistent storage format.
Nor is VXML expected or designed to be typed out by hand, save in limited
situations such as writing small tests.

For document-to-document transpilation, VXML also conveys _blame_ from the
source document and/or an intervening transformation pipeline. Each atomic unit
such as a tag, an attribute, or a line of text carries a `Blame`. This provides
a built-in traceability mechanism. Blames are not encoded in VXML's default
serialization, but a specific emitter can choose to be blame-aware, e.g., to
provide "click to jump back to source"-type functionality.

In this package:

- the `VXML` tree type with recursive element nodes and terminal text nodes,
  built on `Blame`, `Line`, and `Attr`
- `InputLine`/`OutputLine` datatypes that allow `Blame`-aware inspection of line
  sequences before parsing and after emitting
- pretty-printing utilities for "live" VXML documents that include blames in
  two-column table format (line-by-line blames on left, VXML document on right)
- out-of-the-box parsers for XML-ish input and serialized VXML itself
- HTML repair helpers for making damaged HTML palatable to XML-oriented parsers
- serializers for HTML-, XML-, and JSX-like output, as well as VXML itself

## Data Model

The upstream non-recursive payloads are:

- `Blame`: a type for encoding provenance of data, detailed below
- `Line`: `Line(blame: Blame, content: String)` encodes single-line text payload
- `Attr`: `Attr(blame: Blame, key: String, val: String)` encodes an attribute key-value pair

The core recursive tree type is:

```gleam
pub type VXML {
  V(blame: Blame, tag: String, attrs: List(Attr), children: List(VXML))
  T(blame: Blame, lines: List(Line))
}
```

Here:

- `V` is an element node: tag, attributes, and children; note that 'V' stands for 'VXML', since `V` is the recursive variant
- `T` is a text node, that is always a terminal of the tree; a text node should carry one or more lines of text

Note that `Blame`s aside, VXML is built on only four types: `V`, `T`, `Line`
and `Attr`.

Moreover, every `V`, `T`, `Line`, and `Attr` value carries exactly one `Blame`,
stored as its first field, making for a simple mental model.

VXML is semantics-agnostic: tags and attributes are names, not behaviors.

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
        'is not one of VXML's abstractions.'
```

Each line of text appears as a visible quoted line, making newline placement and
whitespace easy to spot by human inspection.

Rules & notes:

- attribute keys must be nonempty and directly followed by `=`; they may not
  contain the `=` char, or spaces
- attribute values are not quoted, should follow `=` directly, and may be
  arbitrary newline-free strings; the final attribute value is
  whitespace-trimmed by the parser, if any trailing whitespace is
  found
- text nodes serialize as anonymous `<>` containers with single-quoted lines;
  the text content of a line is the part between the first `'` and the last
  `'`, so intermediate single quotes do not need to be escaped
- a serialized text line that does not start and end with a single quote is an
  error
- indentation is fixed at two spaces, matching Gleam indentation and allowing
  VXML to be included as block strings in Gleam source
- text nodes must have at least 1 line, though the line can be the empty string

Relevant rules also apply to the VXML datatype itself, even while the type
system is not able to encode some constraints, e.g., the fact that "=" is an
invalid character inside an attribute key. These constraints could have been
enforced via opaque types, but the present package takes a more live and let
live approach, which has advantages in terms of allowing transforms to directly
`case` on VXML values, etc.

Note in particular, however, that a VXML payload is
considered malformed if it contains a `T`-node with an empty list of lines.

## Ingress: Parsing XML and HTML

VXML's XML ingress has two layers. Most callers should use the parser layer,
which converts source text into a VXML tree. Lower-level callers can use
`xml_streamer` directly to tokenize XML-like input before building their own
parser.

For the usual case, convert a string to `InputLine`s and pass them to
`parse_xml_input_lines`:

```gleam
let assert Ok(vxml) =
  source
  |> io_lines.string_to_input_lines("relevant/path/to/source.xml", 0)
  |> vxml.parse_xml_input_lines
```

For direct string input, `parse_xml_string(source, filename)` performs the
`string_to_input_lines` conversion internally.

For HTML-ish input, apply the HTML repair helpers first:

```gleam
let assert Ok(vxml) =
  source
  |> vxml.html_repair
  |> io_lines.string_to_input_lines("source.html", 0)
  |> vxml.parse_xml_input_lines
```

The `html_repair` step:

- expands common boolean attributes, such as `disabled`
- escapes ampersands that are not already HTML entities
- closes HTML void tags, such as `img`, `br`, and `meta`
- removes attributes from malformed closing tags

The individual repair helpers are public so callers can apply only the repair
steps they want.

The tokenizer layer is available through `xml_streamer`. It exposes entry points
for strings and `InputLine`s, returning XML token events rather than VXML. Use
it only when token-level XML access is needed before VXML construction.

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
