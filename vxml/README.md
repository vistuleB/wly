# VXML

An document format for encoding generic XML in a minimalist human-readable form while
treating text as a first-class citizen.

This is a sample document:

```
<> vxmlSample
  attr1=mom
  attr2=dad
  <>
    "this is a text child"
    "with two lines"
  <>
    "this a second text child"
    "second line of the second text child"
    "third line of text of the second text child"
    "etc"
  <> html
    <> header
      charset=utf-8
    <> body
      <> div
        style=padding:10px
        <> p
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
  "I am not a child of vxmlSample"
  "this document is therefore a list of 2 VXML nodes"
```
