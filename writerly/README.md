# writerly

## Introduction

'Writerly' is a syntax-only derivative of [Elm-Markup](https://github.com/mdgriffith/elm-markup). It encodes a superset of XML in human-readable and -writeable form.

The following is a sample Writerly file:

```
|> SomeTag
    attr1=value1
    attr2=value2

    A paragraph with one line.

    A second paragraph.

    |> AnotherTag
        attr3=val3

    |> ol
        |> li
            style=background:red

            Hello world. The 'li'
            to which I, this paragraph, belongs, is
            the granchild of 'SomeTag'.

        |> li
            The first line of this paragraph does not parse as a
            key-value pair, though it directly follows
            a tag; so it will be interpreted as a text, and these
            four lines of text become one paragraph.

    !! lines starting with "!!"
    !! are comments

    !! here is a code block:

    ```python
    def fn(x):
        return x + 1
    ```

    Writerly considers whitespace at the end of a
    text line to have semantic value, and will not trim
    that whitespace. To insert spaces at the beginning
    of a line, start the line with a backslash:
    \        followed
    by the number of spaces you want.

|> ASecondTag

    Writerly files can have multiple top-level nodes.
    This document contains three top-level nodes: 'SomeTag',
    'ASecondTag', as well as...

...this last paragraph, which is
a sibling of 'SomeTag' and 'ASecondTag'.
```

In particular:

- Writerly uses `|> tag` to encode an XML `<tag ...>...</tag>`.
- Writerly parent-child relationships are indentation-based using 4 spaces of indentation.
- Writerly separates paragraphs by blank lines. But note that XML does not have a primitive concept of a "paragraph"—this is why Writerly is a semantic _superset_ of XML!
- Writerly tag attributes (the equivalent of HTML and XML tag attributes) are listed directly below the `|> tag` as lines of the form `key=val` with 4 spaces of indentation. A line that does not parse as an attribute key-value pair is either interpreted as text or as a new node, depending on whether the line starts with `|>` or not. A blank line can also be used to separate the last key-value pair from the first text child, allowing the first text child to start with text of the form `key=val`, that would otherwise be parsed as a tag attribute.
- Blank lines are _bona fide_ semantic elements of the document. Introducing a blank line between two adjacent tags or not may produce different results depending on the desugaring process that is used to process the Writerly document into a target document of a different format.

Writerly documents take extension `.wly`.

## Multi-file documents

Writerly documents are designed to be broken across multiple files for large projects. Consider the following directory contents:

```
./some_dir
  ├─ __parent.wly
  ├─ chapter1.wly
  ├─ chapter2.wly
  └─ chapter3.wly
```

The loader will indent the contents of `chapter1.wly`, `chapter2.wly` and `chapter3.wly` 
by 4 spaces and then append the concatenated contents of those files, according to the lexicographic order
of the filenames, to the contents of `__parent.wly`. This process is pursued recursively through subdirectories.

Writerly files or directories starting with `#` are "commented out" and ignored by the loader.
