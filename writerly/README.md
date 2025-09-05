# writerly

'Writerly' is a syntax-only derivative of [Elm-Markup](https://github.com/mdgriffith/elm-markup). It encodes a superset of XML in human-readable and -writeable form.

Here is a sample document:

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

    !! here is a code block; the
    !! contents of the code block look
    !! like Writerly in this case, but they will not 
    !! parse as such; since they are inside a code block
    !! (they will just parse as verbatim strings):

    ```writerly
    |> SomeTag
        |> Child1
            |> Grandchild1
                attr1=val1
    ```

    Writerly considers whitespace at the end of a
    text line to have semantic value, and will not trim
    that whitespace: To insert spaces at the beginning
    of a line, start the line with a backslash:
    \        followed
    by the number of spaces you want.
```

Note that:

- The Writerly equivalent of an XML `<tag ...>...</tag>` node is `|> tag`.
- XML tag attributes are listed (indented) below the `|> tag` as lines of the form `key=val`; a line that does not parse as an attribute key-value pair is interpreted as text (unless it starts in which case it is interpreted as such); a non-semantic blank line can also be used to separate the last key-value pair from the first paragraph child (or tag child) of a tag.
- Spaces and Writerly character sequences only need to be escaped at the beginning of text lines, but do not need to be escaped within text lines; the escape character is `\`.
- Writerly is indentation-based, with 4 spaces of indentation.