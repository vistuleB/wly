import desugaring/core
import gleam/list
import vxml.{type Line, Line}
import vxml/blame

fn line_contents(lines: List(Line)) -> List(String) {
  lines
  |> list.map(fn(line) { line.content })
}

fn rewrap(
  source_contents: List(String),
  occupied_width: Int,
  max_width: Int,
) -> #(List(String), Int) {
  let lines =
    source_contents
    |> list.map(fn(content) { Line(blame.no_blame, content) })
  let #(lines, final_width) =
    core.line_wrap_rearrangement(lines, occupied_width, max_width)
  #(line_contents(lines), final_width)
}

pub fn main() {
  // Text comfortably below the limit remains on one line.
  assert rewrap(["alpha beta"], 0, 20) == #(["alpha beta"], 10)

  // Wrapping occurs at a word boundary when another word
  // clearly cannot fit.
  assert rewrap(["aa bb cc"], 0, 7) == #(["aa bb", "cc"], 2)

  // An indivisible word is allowed to exceed the limit.
  assert rewrap(["abcdefgh"], 0, 4) == #(["abcdefgh"], 8)

  // Occupied width from preceding inline content contributes
  // to the returned width when no new line is introduced.
  assert rewrap(["aa bb"], 3, 9) == #(["aa bb"], 8)

  // Original line boundaries are reflowed as spaces, and
  // repeated spaces represented by empty tokens are retained.
  assert rewrap(["one", "two"], 0, 20) == #(["one two"], 7)
  assert rewrap(["a  b"], 0, 20) == #(["a  b"], 4)
}
