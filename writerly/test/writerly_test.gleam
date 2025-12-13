import gleeunit
import gleeunit/should
import gleam/string
import writerly.{Paragraph} as wl
import dirtree.{Dirpath, Filepath} as _dt
import blame.{Src} as _bl
import io_lines.{InputLine} as _io_l
import vxml.{Attr, Line}

pub fn main() -> Nil {
  gleeunit.main()
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
  let doc = "
|> Book
    a=b
  " |> string.trim()
  wl.parse_string(doc, "doc")
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
        [Paragraph(Src([], "doc", 4, 5, False), [
          Line(Src([], "doc", 4, 5, False), "first"),
          Line(Src([], "doc", 5, 5, False), "second"),
        ])]
      )
    )
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
}