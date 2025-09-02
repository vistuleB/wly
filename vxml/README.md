# vxml

## Intro

VXML looks like this (text & tag nodes only; tag nodes can have attributes):

```
<> vxmlSample
    attr1=mom
    attr2=dad
    <>
        "this is a text child"
        "with two lines"
    <> html
        <> header
            charset=utf-8
        <> body
            <> div
                <>
                    "some text"
                    "more text"
        <> baz
            <> child1
            <> child2
            <>
                "hello I am the third child of baz,"
                "but the first text child of baz"
            <> child4
<>
    "yello"
```

## Development

```sh
gleam run   # Run the project
```

## What's there

Here is a simplifie version of the VXML type:

```
pub type VXML {
  V(
    tag: String,
    attributes: List(#(String, String)),
    children: List(VXML),
  )
  T(
    contents: List(String)
  )
}
```

This is gleam syntax for "a `VXML` is either a `V` or a `T`, where `V` has these fields and `T` has those fields".

In reality the type is a little more complex every parsed line carries a `Blame`:

```
pub type Blame {
  Blame(filename: String, line_no: Int, char_no: Int, comments: List(String))
}
```

The parser doesn't really care about `Blame` but they are littered everywhere. (They will help us track source across multiple desugarings etc.)

So in fact, the true collection of types, with `Blame` everywhere, is like so:

```
pub type Blame {
  Blame(filename: String, line_no: Int, comments: List(String))
}

pub type Line {
  Line(blame: Blame, content: String)
}

pub type Attribute {
  Attribute(blame: Blame, key: String, value: String)
}

pub type VXML {
  V(
    blame: Blame,
    tag: String,
    attributes: List(Attribute),
    children: List(VXML),
  )
  T(blame: Blame, contents: List(Line))
}
```

We also have a parser error type:

```
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
}
```
