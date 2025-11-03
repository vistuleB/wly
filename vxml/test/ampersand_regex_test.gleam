import gleeunit/should
import vxml
import gleam/regexp

pub fn main() {
  let assert Ok(a) = regexp.from_string(vxml.non_html_ampersand_re)
  regexp.replace(a, " &amp;&Gamma; ", "&amp;")
  |> echo
  |> should.equal(" &amp;&amp;Gamma; ")
  regexp.replace(a, " &a#a; ", "&amp;")
  |> echo
  |> should.equal(" &amp;a#a; ")
}
