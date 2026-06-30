import gleeunit
import gleeunit/should
import vxml

pub fn main() {
  gleeunit.main()
}

pub fn close_html_void_tags_test() {
  "<div><img src=\"x\"><br><input disabled></div>"
  |> vxml.close_html_void_tags
  |> should.equal("<div><img src=\"x\"/><br/><input disabled/></div>")
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

pub fn bad_html_pre_processor_combines_html_repairs_test() {
  "<img src=\"x\"><span>body</span class=\"old\">"
  |> vxml.bad_html_pre_processor
  |> should.equal("<img src=\"x\"/><span>body</span>")
}
