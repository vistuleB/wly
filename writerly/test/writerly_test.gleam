import dirtree.{Dirpath, Filepath} as _dt
import gleam/list
import gleam/option
import gleam/string
import gleeunit
import gleeunit/should
import vxml.{Attr, Line}
import vxml/blame.{Anchored, Movable, Src} as _bl
import vxml/io_lines.{InputLine} as io_l
import writerly.{type Writerly, Paragraph} as wl

pub fn main() -> Nil {
  gleeunit.main()
}

fn trim_end_spaces_and_one_newline(q: String) -> String {
  case string.ends_with(q, " ") {
    True -> q |> string.drop_end(1) |> trim_end_spaces_and_one_newline
    False ->
      case string.ends_with(q, "\n") {
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

pub fn assembler_reads_a_single_file_with_relative_blame_paths_test() {
  wl.assemble_input_lines("test/test1.wly")
  |> should.equal(
    Ok(
      #(Dirpath("test", [Filepath("test1.wly")]), [
        InputLine(Src([], "test1.wly", 1, 1, Movable), 0, "|> Book"),
        InputLine(Src([], "test1.wly", 2, 5, Movable), 4, "bob=2"),
        InputLine(Src([], "test1.wly", 3, 5, Movable), 4, "cuchua"),
        InputLine(Src([], "test1.wly", 4, 1, Movable), 0, ""),
      ]),
    ),
  )
}

pub fn assembler_nests_child_files_below_the_parent_document_test() {
  wl.assemble_input_lines("test/testA")
  |> should.equal(
    Ok(
      #(
        Dirpath("test/testA", [Filepath("__parent.wly"), Filepath("childA.wly")]),
        [
          InputLine(Src([], "__parent.wly", 1, 1, Movable), 0, "|> Book"),
          InputLine(Src([], "__parent.wly", 2, 5, Movable), 4, "a=b"),
          InputLine(
            Src([], "childA.wly", 1, 1, Movable),
            4,
            "It was a dark and stormy night.",
          ),
        ],
      ),
    ),
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

pub fn parser_builds_a_tag_with_an_attribute_test() {
  let wly_doc =
    "
|> Book
    a=b
  "
    |> string.trim()
  wl.string_to_writerlys(wly_doc, "doc")
  |> should.equal(
    Ok([
      wl.Tag(
        Src([], "doc", 1, 1, Anchored),
        "Book",
        [
          Attr(Src([], "doc", 2, 5, Movable), "a", "b"),
        ],
        [],
      ),
    ]),
  )
}

pub fn parser_preserves_paragraph_source_blame_test() {
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
          Paragraph(Src([], "test1.wly", 3, 5, Movable), [
            Line(Src([], "test1.wly", 3, 5, Movable), "cuchua"),
          ]),
        ],
      ),
    ]),
  )
}

pub fn parser_preserves_blame_across_assembled_files_test() {
  let assert Ok(#(_tree, lines)) = wl.assemble_input_lines("test/testA")
  lines
  |> wl.input_lines_to_writerlys()
  |> should.equal(
    Ok([
      wl.Tag(
        Src([], "__parent.wly", 1, 1, Anchored),
        "Book",
        [
          Attr(Src([], "__parent.wly", 2, 5, Movable), "a", "b"),
        ],
        [
          Paragraph(Src([], "childA.wly", 1, 1, Movable), [
            Line(
              Src([], "childA.wly", 1, 1, Movable),
              "It was a dark and stormy night.",
            ),
          ]),
        ],
      ),
    ]),
  )
}

pub fn writerly_tag_converts_to_vxml_element_test() {
  let wly_doc =
    "
|> Book
    a=b
  "
    |> string.trim()

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

pub fn vxml_text_node_converts_to_writerly_paragraph_test() {
  let vxml_doc =
    "
<> Book
  a=b
  <>
    'first'
    'second'
  "
    |> string.trim

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
          Paragraph(Src([], "doc", 4, 5, Movable), [
            Line(Src([], "doc", 4, 5, Movable), "first"),
            Line(Src([], "doc", 5, 5, Movable), "second"),
          ]),
        ],
      ),
    ),
  )
}

fn should_parse_and_serialize_without_change(source: String) {
  source
  |> parse_ergonomic_wly("doc")
  |> wl.writerly_to_string
  |> should.equal(
    source
    |> ergonomic_source_to_standard_source,
  )
}

pub fn serializer_preserves_escaped_code_fences_test() {
  "
  |> Book
    a=b
    ```
    \\```
    ```
  "
  |> should_parse_and_serialize_without_change
}

pub fn serializer_preserves_escaped_paragraph_indentation_test() {
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
  |> should_parse_and_serialize_without_change
}

pub fn serializer_preserves_comments_and_trailing_spaces_test() {
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
  |> should_parse_and_serialize_without_change
}

pub fn commented_attribute_encoding_test() {
  let source = "|> Book\n    !!   someguy=aa"
  let assert Ok(writerly) = wl.string_to_writerly(source, "doc")
  let assert wl.Tag(_, "Book", [Attr(_, key, val)], []) = writerly

  key |> should.equal("WriterlyCommentedAttribute3Spaces")
  val |> should.equal("someguy=aa")
  writerly |> wl.writerly_to_string |> should.equal(source)

  let empty_source = "|> Book\n    !!"
  let assert Ok(empty_writerly) = wl.string_to_writerly(empty_source, "doc")
  let assert wl.Tag(_, "Book", [Attr(_, empty_key, "")], []) = empty_writerly
  empty_key |> should.equal("WriterlyCommentedAttribute0Spaces")
  empty_writerly |> wl.writerly_to_string |> should.equal(empty_source)
}

pub fn commented_attribute_key_helpers_test() {
  wl.commented_attribute_spaces("WriterlyCommentedAttribute0Spaces")
  |> should.equal(option.Some(0))
  wl.commented_attribute_spaces("WriterlyCommentedAttribute1000Spaces")
  |> should.equal(option.Some(1000))
  wl.is_commented_attribute_key("WriterlyCommentedAttribute1001Spaces")
  |> should.be_false
  wl.commented_attribute_spaces("WriterlyCommentedAttribute01Spaces")
  |> should.equal(option.Some(1))
}
