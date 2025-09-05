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

    !! here is a code block:

    ```python
    def fn(x):
        return x + 1
    ```

    Writerly considers whitespace at the end of a
    text line to have semantic value, and will not trim
    that whitespace: To insert spaces at the beginning
    of a line, start the line with a backslash:
    \        followed
    by the number of spaces you want.
```

One can note that:

- The Writerly equivalent of an XML `<tag ...>...</tag>` node is `|> tag`.
- XML tag attributes are listed (indented) below the `|> tag` as lines of the form `key=val`; a line that does not parse as an attribute key-value pair is interpreted as text (unless it starts with `|>` in which case it is interpreted as a tag, of course); a blank line can also be used to separate the last key-value pair from the first paragraph child (or tag child) of a tag.
- Spaces and Writerly character sequences only need to be escaped at the beginning of text lines, but do not need to be escaped within text lines; the escape character is `\`.
- Writerly is indentation-based, with 4 spaces of indentation.

Writerly documents take extension `.wly`.

Writerly documents can be broken across multiple files for large projects. Consider the following directory structure:

```
some_dir
├─ __parent.wly
├─ chapter1.wly
├─ chapter2.wly
└─ chapter3.wly
```

The loader will indent the contents of `chapter1.wly`, `chapter2.wly` and `chapter3.wly` 
by 4 spaces and then append the concatenated contents of those files (according to the lexicographic order
of the filenames) to the contents `__parent.wly`. This process is pursued recursively with subdirectories.
This is an example directory structure:

```
some_dir
├─ __parent.wly
├─ tome1
│  ├─ __parent.wly
│  ├─ 01-ALongAwaitedParty.wly
│  ├─ 02-AnUnexpectedVisit.wly
│  └─ 03-OverHillAndUnderhill.wly
├─ tome2
│  ├─ __parent.wly
│  ├─ 01-TheCloudsGather.wly
│  ├─ 02-TheCloudsBurst.wly
│  ├─ 03-AnUnexpectedVisitInTome2.wly
│  └─ 04-OverHillAndUnderhillInTome2.wly
└─ tome3
   ├─ __parent.wly
   ├─ 01-primitive-recursion-definitions.wly
   ├─ 02-primitive-recursion-constructions.wly
   ├─ 03-ackermann.wly
   └─ 04-mu-recursion.wly
```

Here the contents of `tome1`, `tome2` and `tome3` will be individually by the same process as described above,
then indented and collated to the topmost `__parent.wly` file.

Writerly files or directories starting with `#` are ignored by the loader.
