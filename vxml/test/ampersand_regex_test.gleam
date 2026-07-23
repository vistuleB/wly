import gleeunit/should
import vxml

pub fn main() {
  " &amp;&Gamma; "
  |> vxml.html_repair_escape_non_entity_ampersands
  |> echo
  |> should.equal(" &amp;&Gamma; ")
  " &a#a; "
  |> vxml.html_repair_escape_non_entity_ampersands
  |> echo
  |> should.equal(" &amp;a#a; ")
}
