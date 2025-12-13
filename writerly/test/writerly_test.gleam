import gleeunit/should
import gleeunit
import writerly as wl
import dirtree.{Dirpath, Filepath} as _dt
import blame.{Src} as _bl
import io_lines.{InputLine} as _io_l

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn part_1_test() {
  wl.assemble_input_lines("test/test1.wly", [])
  |> should.equal(
    Ok(#(
      Dirpath("test", [Filepath("test1.wly")]),
      [
        InputLine(Src([], "test1.wly", 1, 1, False), 0, "|> Book"),
        InputLine(Src([], "test1.wly", 2, 5, False), 4, "bob=2"),
        InputLine(Src([], "test1.wly", 3, 5, False), 4, "cuchua"),
        InputLine(Src([], "test1.wly", 4, 1, False), 0, ""),
      ],
    )),
  )

  wl.assemble_input_lines("test/testA", [])
  |> should.equal(
    Ok(#(
      Dirpath("test/testA", [Filepath("__parent.wly"), Filepath("childA.wly")]),
      [
        InputLine(Src([], "__parent.wly", 1, 1, False), 0, "|> Book"), 
        InputLine(Src([], "__parent.wly", 2, 5, False), 4, "a=b"), 
        InputLine(Src([], "childA.wly", 1, 1, False), 4, "It was a dark and stormy night."),
      ],
    )),
  )
}