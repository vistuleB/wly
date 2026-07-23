import gleeunit
import gleeunit/should
import gleam/string
import gleam/list
import writerly.{type Writerly, Paragraph} as wl
import dirtree.{Dirpath, Filepath} as _dt
import blame.{Anchored, Movable, Src} as _bl
import io_lines.{InputLine} as io_l
import simplifile
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
  let assert Ok(writerly) =
    source
    |> ergonomic_source_to_standard_source
    |> wl.string_to_writerly(name)
  writerly
}

pub fn part_1_test() {
  wl.assemble_input_lines("test/test1.wly")
  |> should.equal(
    Ok(#(
      Dirpath("test", [Filepath("test1.wly")]),
      [
        InputLine(Src([], "test1.wly", 1, 1, Movable), 0, "|> Book"),
        InputLine(Src([], "test1.wly", 2, 5, Movable), 4, "bob=2"),
        InputLine(Src([], "test1.wly", 3, 5, Movable), 4, "cuchua"),
        InputLine(Src([], "test1.wly", 4, 1, Movable), 0, ""),
      ],
    )),
  )

  wl.assemble_input_lines("test/testA")
  |> should.equal(
    Ok(#(
      Dirpath("test/testA", [Filepath("__parent.wly"), Filepath("childA.wly")]),
      [
        InputLine(Src([], "__parent.wly", 1, 1, Movable), 0, "|> Book"), 
        InputLine(Src([], "__parent.wly", 2, 5, Movable), 4, "a=b"), 
        InputLine(Src([], "childA.wly", 1, 1, Movable), 4, "It was a dark and stormy night."),
      ],
    )),
  )
}

pub fn path_selector_from_only_paths_test() {
  let include_chapter_1 = wl.path_selector_from_only_paths(["chapter-1"])
  include_chapter_1("book/chapter-1/section.wly")
  |> should.be_true
  include_chapter_1("book/chapter-2/section.wly")
  |> should.be_false

  let exclude_draft = wl.path_selector_from_only_paths(["!draft"])
  exclude_draft("book/chapter-1/section.wly")
  |> should.be_true
  exclude_draft("book/draft/section.wly")
  |> should.be_false

  let include_chapter_1_but_exclude_draft =
    wl.path_selector_from_only_paths(["chapter-1", "!draft"])
  include_chapter_1_but_exclude_draft("book/chapter-1/section.wly")
  |> should.be_true
  include_chapter_1_but_exclude_draft("book/chapter-1/draft/section.wly")
  |> should.be_false
  include_chapter_1_but_exclude_draft("book/chapter-2/section.wly")
  |> should.be_false
}

pub fn sample_wly_parses_and_roundtrips_test() {
  let assert Ok(contents) = simplifile.read("samples/sample.wly")
  let assert Ok(writerlys) = wl.string_to_writerlys(contents, "samples/sample.wly")

  writerlys
  |> list.length
  |> should.equal(1)

  writerlys
  |> wl.writerlys_to_string
  |> should.equal(contents |> string.trim_end)
}

pub fn sample_contents_directory_assembles_and_parses_test() {
  let assert Ok(#(_tree, lines)) =
    wl.assemble_input_lines("samples/contents/ch5_ch.wly")

  lines
  |> list.length
  |> fn(length) { length > 0 }
  |> should.be_true

  let assert Ok(writerlys) = wl.input_lines_to_writerlys(lines)

  writerlys
  |> list.length
  |> should.equal(1)

  writerlys
  |> list.map(wl.writerly_to_vxml)
  |> list.length
  |> should.equal(1)
}

pub fn sample_xml_converts_to_writerly_test() {
  let assert Ok(contents) = simplifile.read("samples/ch5_ch.xml")
  let assert Ok(node) =
    contents
    |> vxml.html_repair
    |> vxml.parse_xml("samples/ch5_ch.xml")

  let writerlys = wl.vxml_to_writerlys(node)

  writerlys
  |> list.length
  |> fn(length) { length > 0 }
  |> should.be_true

  writerlys
  |> list.map(wl.writerly_to_string)
  |> string.concat
  |> string.is_empty
  |> should.be_false
}

pub fn part_2_test() {
  let wly_doc = "
|> Book
    a=b
  " |> string.trim()
  wl.string_to_writerlys(wly_doc, "doc")
  |> should.equal(Ok([
    wl.Tag(
      Src([], "doc", 1, 1, Anchored),
      "Book",
      [
        Attr(Src([], "doc", 2, 5, Movable), "a", "b"),
      ],
      [],
    ),
  ]))

  let assert Ok(#(_tree, lines)) = wl.assemble_input_lines("test/test1.wly")

  lines
  |> wl.input_lines_to_writerlys()
  |> should.equal(
    Ok([
      wl.Tag(
        Src([], "test1.wly", 1, 1, Anchored),
        "Book",
        [
          Attr(Src([], "test1.wly", 2, 5, Movable), "bob", "2"),
        ],
        [
          Paragraph(
            Src([], "test1.wly", 3, 5, Movable),
            [
              Line(Src([], "test1.wly", 3, 5, Movable), "cuchua")
            ],
          ),
        ]
      )]
    )
  )

  let assert Ok(#(_tree, lines)) = wl.assemble_input_lines("test/testA")
  lines
  |> wl.input_lines_to_writerlys()
  |> should.equal(
    Ok([
      wl.Tag(
        Src([], "__parent.wly", 1, 1, Anchored), "Book",
        [
          Attr(Src([], "__parent.wly", 2, 5, Movable), "a", "b"),
        ],
        [
          Paragraph(
            Src([], "childA.wly", 1, 1, Movable),
            [
              Line(Src([], "childA.wly", 1, 1, Movable), "It was a dark and stormy night."),
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

  let assert Ok(wly_parsed) = wl.string_to_writerly(wly_doc, "doc")

  wly_parsed
  |> wl.writerly_to_vxml()
  |> should.equal(
    vxml.V(
      Src([], "doc", 1, 1, Anchored),
      "Book",
      [Attr(Src([], "doc", 2, 5, Movable), "a", "b")],
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

  let assert Ok([vxml_parsed]) = vxml.parse_string(vxml_doc, "doc", True)

  vxml_parsed
  |> wl.vxml_to_writerly
  |> should.equal(
    Ok(
      wl.Tag(
        Src([], "doc", 1, 1, Anchored),
        "Book",
        [Attr(Src([], "doc", 2, 3, Movable), "a", "b")],
        [
          Paragraph(
            Src([], "doc", 4, 5, Movable),
            [
              Line(Src([], "doc", 4, 5, Movable), "first"),
              Line(Src([], "doc", 5, 5, Movable), "second"),
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

  let assert Ok(wly_parsed) = wl.string_to_writerly(wly_doc, "doc")

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
      Src([], "doc", 1, 1, Anchored),
      "Book",
      [
        Attr(Src([], "doc", 2, 5, Movable), "a", "b"),
        Attr(Src([], "doc", 3, 5, Movable), "qqq", "z"),
      ],
      [],
    ),
  )
}
