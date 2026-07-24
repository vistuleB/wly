import blame.{Anchored, Movable, Src}
import gleam/list
import gleam/string
import gleeunit
import gleeunit/should
import io_lines
import simplifile
import vxml.{type Attr, type VXML, Attr, Line, T, V}
import xmlm

fn xmlm_attr_to_vxml_attrs(
  filename: String,
  line_no: Int,
  xmlm_attr: xmlm.Attribute,
) -> Attr {
  let blame = Src([], filename, line_no, 0, Movable)
  Attr(blame, xmlm_attr.name.local, xmlm_attr.value)
}

fn xmlm_based_html_parser(
  content: String,
  filename: String,
) -> Result(VXML, xmlm.InputError) {
  let input = content |> vxml.html_repair |> xmlm.from_string

  case
    xmlm.document_tree(
      input,
      fn(xmlm_tag, children) {
        V(
          Src([], filename, 0, 0, Anchored),
          xmlm_tag.name.local,
          xmlm_tag.attributes
            |> list.map(xmlm_attr_to_vxml_attrs(filename, 0, _)),
          children,
        )
      },
      fn(content) {
        let lines =
          content
          |> string.split("\n")
          |> list.map(fn(content) {
            Line(Src([], filename, 0, 0, Movable), content)
          })
        T(Src([], filename, 0, 0, Movable), lines)
      },
    )
  {
    Ok(#(_, vxml, _)) -> Ok(vxml)
    Error(input_error) -> Error(input_error)
  }
}

pub fn main() {
  gleeunit.main()
}

pub fn parse_and_serialize_roundtrip_test() {
  let source = "<> Book\n  title=Example\n  <>\n    'hello'\n  <> Chapter"

  let assert Ok(parsed) = vxml.parse_string(source, "sample.vxml", True)

  parsed
  |> vxml.vxmls_to_string
  |> should.equal(source)
}

pub fn parse_string_rejects_multiple_roots_when_unique_root_test() {
  "<> One\n<> Two"
  |> vxml.parse_string("sample.vxml", True)
  |> should.equal(Error(vxml.VXMLParseErrorNonUniqueRoot(2)))
}

pub fn validate_tag_accepts_serialized_vxml_tag_names_test() {
  "Chapter_2"
  |> vxml.validate_tag
  |> should.equal(Ok("Chapter_2"))
}

pub fn validate_tag_rejects_dot_and_hyphen_test() {
  "chapter.2"
  |> vxml.validate_tag
  |> should.equal(
    Error(vxml.MalformedTag("chapter.2", "^[A-Za-z][A-Za-z0-9_]*$")),
  )

  "chapter-2"
  |> vxml.validate_tag
  |> should.equal(
    Error(vxml.MalformedTag("chapter-2", "^[A-Za-z][A-Za-z0-9_]*$")),
  )
}

pub fn validate_tag_rejects_digit_start_test() {
  "2Chapter"
  |> vxml.validate_tag
  |> should.equal(
    Error(vxml.MalformedTag("2Chapter", "^[A-Za-z][A-Za-z0-9_]*$")),
  )
}

pub fn html_parser_accepts_common_html_repairs_test() {
  "<html><body><img src=\"x\"><input disabled><p>fish & chips</p></body></html>"
  |> xmlm_based_html_parser("sample.html")
  |> should.be_ok
}

pub fn html_output_escapes_text_test() {
  let assert Ok([node]) =
    "<> p\n  <>\n    'fish & chips < ok >'"
    |> vxml.parse_string("sample.vxml", True)

  node
  |> vxml.vxml_to_html_output_lines(0, 2)
  |> io_lines.output_lines_to_string
  |> should.equal("<p>\n  fish &amp; chips &lt; ok &gt;\n</p>")
}

pub fn sample_vxml_file_parses_test() {
  let assert Ok(vxmls) = vxml.parse_file("samples/sample.vxml", False)

  vxmls
  |> list.length
  |> should.equal(2)
}

pub fn sample_html_file_parses_and_emits_test() {
  let assert Ok(content) = simplifile.read("samples/sample.html")
  let assert Ok(node) = xmlm_based_html_parser(content, "samples/sample.html")

  node
  |> vxml.vxml_to_html_output_lines(0, 2)
  |> list.length
  |> fn(length) { length > 0 }
  |> should.be_true
}

pub fn sample_html_streaming_parser_returns_one_root_test() {
  let assert Ok(content) = simplifile.read("samples/sample2.html")

  content
  |> vxml.html_repair
  |> vxml.parse_xml("samples/sample2.html")
  |> should.be_ok
}

pub fn html_repair_close_void_tags_test() {
  "<div><img src=\"x\"><br><input disabled></div>"
  |> vxml.html_repair_close_void_tags
  |> should.equal("<div><img src=\"x\"/><br/><input disabled/></div>")
}

pub fn html_repair_escape_non_entity_ampersands_test() {
  "fish & chips &Gamma;"
  |> vxml.html_repair_escape_non_entity_ampersands
  |> should.equal("fish &amp; chips &Gamma;")
}

pub fn html_repair_expand_boolean_attrs_test() {
  "<script async src=\"x\"></script><input disabled/>"
  |> vxml.html_repair_expand_boolean_attrs
  |> should.equal(
    "<script async=\"\" src=\"x\"></script><input disabled=\"\"/>",
  )
}

pub fn html_repair_close_void_tags_leaves_already_closed_tags_test() {
  "<meta charset=\"utf-8\"/><hr/>"
  |> vxml.html_repair_close_void_tags
  |> should.equal("<meta charset=\"utf-8\"/><hr/>")
}

pub fn html_repair_remove_attrs_from_closing_tags_uses_each_tag_match_test() {
  "</span class=\"x\"></div id=\"main\"></a href=\"/somewhere\">"
  |> vxml.html_repair_remove_attrs_from_closing_tags
  |> should.equal("</span></div></a>")
}

pub fn html_repair_remove_attrs_from_closing_tags_supports_parser_tag_names_test() {
  "</x-tag data-old=\"1\"></x.name data-old=\"2\"></x_tag data-old=\"3\">"
  |> vxml.html_repair_remove_attrs_from_closing_tags
  |> should.equal("</x-tag></x.name></x_tag>")
}

pub fn html_repair_combines_html_repairs_test() {
  "<img src=\"x\"><span>body</span class=\"old\">"
  |> vxml.html_repair
  |> should.equal("<img src=\"x\"/><span>body</span>")
}
