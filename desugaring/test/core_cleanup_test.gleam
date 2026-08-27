import desugaring/core
import desugaring/tracking
import vxml.{Line, T}
import vxml/blame

pub fn main() {
  let assert [tracking.TSLine(..), tracking.LSLine(..)] =
    T(blame.no_blame, [Line(blame.no_blame, "text")])
    |> tracking.vxml_to_s_lines

  assert core.list_set([1, 2, 3], 1, 4) == [1, 4, 3]
}
