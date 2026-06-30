import blame
import gleeunit/should

pub fn advance_moves_movable_source_cursor_test() {
  blame.Src([], "doc.wly", 3, 5, blame.Movable)
  |> blame.advance(4)
  |> should.equal(blame.Src([], "doc.wly", 3, 9, blame.Movable))
}

pub fn advance_keeps_anchored_source_cursor_fixed_test() {
  blame.Src([], "doc.wly", 3, 5, blame.Anchored)
  |> blame.advance(4)
  |> should.equal(blame.Src([], "doc.wly", 3, 5, blame.Anchored))
}

pub fn set_anchored_changes_source_cursor_test() {
  blame.Src([], "doc.wly", 3, 5, blame.Movable)
  |> blame.set_anchored
  |> should.equal(blame.Src([], "doc.wly", 3, 5, blame.Anchored))
}

pub fn blame_digest_marks_anchored_source_cursor_test() {
  blame.Src([], "doc.wly", 3, 5, blame.Anchored)
  |> blame.blame_digest
  |> should.equal("doc.wly:3:5 ->")
}
