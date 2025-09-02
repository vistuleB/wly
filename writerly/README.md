# writerly

## Intro

"Writerly" is a derivative of Elm-Markup. It encodes a superset of XML. It is built on three primitives:

- xml-like nodes with key-value attribute pairs and children, where the children may be selfsame nodes or:
- multi-line text blurbs, or:
- triple-backquoted code blocks

Parent-child relationships are indicated by indentation, with four spaces of indentation.

Key-value attributes in the form `key=val` are defined on the lines immediately following the node tag, which has the form `|> Tag`.

Lines of whitespace are used to separate text blurbs from one another

Sample:

```
|> SomeTag
    attr1=value1
    attr2=value2

    A paragraph with one line.

    A paragraph
    with
    four small
    lines.

    |> Child1
        attr3=val3

    |> ol
        |> li
            style=background:red

            Hello world. The 'li'
            to which I, this paragraph, belongs, is
            the granchild of 'SomeTag', and the child
            of 'ol'.

        |> li
            This text does not parse as a
            key-value pair, though it directly follows
            a tag; so it will become the
            first paragraph child this node.

    !! lines starting with "!!"
    !! are comments
    !!
    !! this is all
    !!
    !! one big...
    !!
    !! ...comment

    ```python
    j
     |> FakeTag
      ```python
      lll
    qqq
    ```
```
...
