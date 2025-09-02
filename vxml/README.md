# vxml

## Intro

VXML looks like this (text & tag nodes only; tag nodes can have attributes); 2 spaces of indentation:

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
