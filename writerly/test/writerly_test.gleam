import gleeunit
import gleeunit/should
import gleam/string
import gleam/list
import writerly.{type Writerly, Paragraph} as wl
import dirtree.{Dirpath, Filepath} as _dt
import blame.{Src} as _bl
import io_lines.{InputLine} as io_l
import vxml.{Attr, Line}

pub fn main() -> Nil {
  gleeunit.main()
}

fn trim_end_spaces_and_one_newline(q: String) -> String {
  case string.ends_with(q, " ") {
    True -> q |> string.drop_end(1) |> trim_end_spaces_and_one_newline
    False -> case string.ends_with(q, "\n") {
      True -> q |> string.drop_end(1)
      False -> q
    }
  }
}

fn ergonomic_source_trim(source: String) -> String {
  case string.starts_with(source, "\n") {
    True -> string.drop_start(source, 1) |> trim_end_spaces_and_one_newline
    False -> source |> trim_end_spaces_and_one_newline
  }
}

// this allows to load a Writerly document written as a multi-line
// string with two spaces of indentations and an initial arbitrary
// indentation and to pretend as if it had 4 spaces of indentation
// and an initial indentation of 0:
fn ergonomic_source_to_standard_source(source: String) -> String {
  let lines =
    source
    |> ergonomic_source_trim
    |> io_l.string_to_input_lines("", 0)

  let assert [first, ..] = lines

  lines
  |> list.map(fn(l) { InputLine(..l, indent: { l.indent - first.indent } * 2) })
  |> io_l.input_lines_to_string
}

// see comment above
fn parse_ergonomic_wly(source: String, name: String) -> Writerly {
  let assert Ok([writerly]) =
    source
    |> ergonomic_source_to_standard_source
    |> wl.parse_string(name)
  writerly
}

pub fn part_1_test() {
  wl.assemble_input_lines("test/test1.wly", [])
  |> should.equal(
    Ok(#(
      Dirpath("test", [Filepath("test1.wly")]),
      [
        InputLine(Src([], "test1.wly", 1, 1, False), 0, "|> Book"),
        InputLine(Src([], "test1.wly", 2, 5, False), 4, "bob=2"),
        InputLine(Src([], "test1.wly", 3, 5, False), 4, "cuchua"),
        InputLine(Src([], "test1.wly", 4, 1, False), 0, ""),
      ],
    )),
  )

  wl.assemble_input_lines("test/testA", [])
  |> should.equal(
    Ok(#(
      Dirpath("test/testA", [Filepath("__parent.wly"), Filepath("childA.wly")]),
      [
        InputLine(Src([], "__parent.wly", 1, 1, False), 0, "|> Book"), 
        InputLine(Src([], "__parent.wly", 2, 5, False), 4, "a=b"), 
        InputLine(Src([], "childA.wly", 1, 1, False), 4, "It was a dark and stormy night."),
      ],
    )),
  )
}

pub fn part_2_test() {
  let wly_doc = "
|> Book
    a=b
  " |> string.trim()
  wl.parse_string(wly_doc, "doc")
  |> should.equal(Ok([
    wl.Tag(
      Src([], "doc", 1, 1, True),
      "Book",
      [
        Attr(Src([], "doc", 2, 5, False), "a", "b"),
      ],
      [],
    ),
  ]))

  let assert Ok(#(_tree, lines)) = wl.assemble_input_lines("test/test1.wly", [])

  lines
  |> wl.parse_input_lines()
  |> should.equal(
    Ok([
      wl.Tag(
        Src([], "test1.wly", 1, 1, True),
        "Book",
        [
          Attr(Src([], "test1.wly", 2, 5, False), "bob", "2"),
        ],
        [
          Paragraph(
            Src([], "test1.wly", 3, 5, False),
            [
              Line(Src([], "test1.wly", 3, 5, False), "cuchua")
            ],
          ),
        ]
      )]
    )
  )

  let assert Ok(#(_tree, lines)) = wl.assemble_input_lines("test/testA", [])
  lines
  |> wl.parse_input_lines()
  |> should.equal(
    Ok([
      wl.Tag(
        Src([], "__parent.wly", 1, 1, True), "Book",
        [
          Attr(Src([], "__parent.wly", 2, 5, False), "a", "b"),
        ],
        [
          Paragraph(
            Src([], "childA.wly", 1, 1, False),
            [
              Line(Src([], "childA.wly", 1, 1, False), "It was a dark and stormy night."),
            ],
          ),
        ],
      ),
    ])
  )
}

pub fn part_3_test() {
  let wly_doc = "
|> Book
    a=b
  " |> string.trim()

  let assert Ok([wly_parsed]) = wl.parse_string(wly_doc, "doc")

  wly_parsed
  |> wl.writerly_to_vxml()
  |> should.equal(
    vxml.V(
      Src([], "doc", 1, 1, True),
      "Book",
      [Attr(Src([], "doc", 2, 5, False), "a", "b")],
      [],
    ),
  )
}

pub fn part_4_test() {
  let vxml_doc = "
<> Book
  a=b
  <>
    'first'
    'second'
  " |> string.trim

  let assert Ok([vxml_parsed]) = vxml.parse_string(vxml_doc, "doc")

  vxml_parsed
  |> wl.vxml_to_writerly
  |> should.equal(
    Ok(
      wl.Tag(
        Src([], "doc", 1, 1, True),
        "Book",
        [Attr(Src([], "doc", 2, 3, False), "a", "b")],
        [
          Paragraph(
            Src([], "doc", 4, 5, False),
            [
              Line(Src([], "doc", 4, 5, False), "first"),
              Line(Src([], "doc", 5, 5, False), "second"),
            ]
          ),
        ],
      )
    )
  )
}

fn parse_and_serialize_verification_for_ergonomic_source(
  source: String,
) {
  source
  |> parse_ergonomic_wly("doc")
  |> wl.writerly_to_string
  |> should.equal(
    source
    |> ergonomic_source_to_standard_source
  )
}

pub fn part_5_test() {
  let wly_doc = "
|> Book
    a=b
  " |> string.trim()

  let assert Ok([wly_parsed]) = wl.parse_string(wly_doc, "doc")

  wly_parsed
  |> wl.writerly_to_string
  |> should.equal(wly_doc)

  "
  |> Book
    a=b
    ```
    \\```
    ```
  "
  |> parse_and_serialize_verification_for_ergonomic_source

  "
  |> Book
    a=b
    ```
    \\```
    ```

    A paragraph with
    \\ an escaped space
    at the beginning of the second line
  "
  |> parse_and_serialize_verification_for_ergonomic_source
  "
  |> Book
    a=b
    !!someguy=aa
    t=w

    ```
      hallo
    \\```
    \\\\```
    ```

    A paragraph with  
    \\ an escaped space
    \\\\ an escaped space
    at the beginning of the second line   
  "
  |> parse_and_serialize_verification_for_ergonomic_source
}

pub fn parse_ergonomic_wly_test() {
  "
  |> Book
    a=b
    qqq=z
  "
  |> parse_ergonomic_wly("doc")
  |> should.equal(
    wl.Tag(
      Src([], "doc", 1, 1, True),
      "Book",
      [
        Attr(Src([], "doc", 2, 5, False), "a", "b"),
        Attr(Src([], "doc", 3, 5, False), "qqq", "z"),
      ],
      [],
    ),
  )
}