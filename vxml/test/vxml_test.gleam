import gleeunit
import gleeunit/should
import gleam/list
import io_lines
import simplifile
import vxml

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

pub fn html_parser_accepts_common_html_repairs_test() {
  "<html><body><img src=\"x\"><input disabled><p>fish & chips</p></body></html>"
  |> vxml.xmlm_based_html_parser("sample.html")
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
  let assert Ok(node) = vxml.xmlm_based_html_parser(content, "samples/sample.html")

  node
  |> vxml.vxml_to_html_output_lines(0, 2)
  |> list.length
  |> fn(length) { length > 0 }
  |> should.be_true
}

pub fn sample_html_streaming_parser_returns_one_root_test() {
  let assert Ok(content) = simplifile.read("samples/sample2.html")

  content
  |> vxml.streaming_based_xml_parser_string_version("samples/sample2.html")
  |> should.be_ok
}

pub fn close_html_void_tags_test() {
  "<div><img src=\"x\"><br><input disabled></div>"
  |> vxml.close_html_void_tags
  |> should.equal("<div><img src=\"x\"/><br/><input disabled/></div>")
}

pub fn escape_non_entity_ampersands_test() {
  "fish & chips &Gamma;"
  |> vxml.escape_non_entity_ampersands
  |> should.equal("fish &amp; chips &Gamma;")
}

pub fn expand_html_boolean_attrs_test() {
  "<script async src=\"x\"></script><input disabled/>"
  |> vxml.expand_html_boolean_attrs
  |> should.equal("<script async=\"\" src=\"x\"></script><input disabled=\"\"/>")
}

pub fn close_html_void_tags_leaves_already_closed_tags_test() {
  "<meta charset=\"utf-8\"/><hr/>"
  |> vxml.close_html_void_tags
  |> should.equal("<meta charset=\"utf-8\"/><hr/>")
}

pub fn remove_attrs_from_closing_tags_uses_each_tag_match_test() {
  "</span class=\"x\"></div id=\"main\"></a href=\"/somewhere\">"
  |> vxml.remove_attrs_from_closing_tags
  |> should.equal("</span></div></a>")
}

pub fn xml_parser_html_repair_combines_html_repairs_test() {
  "<img src=\"x\"><span>body</span class=\"old\">"
  |> vxml.xml_parser_html_repair
  |> should.equal("<img src=\"x\"/><span>body</span>")
}
