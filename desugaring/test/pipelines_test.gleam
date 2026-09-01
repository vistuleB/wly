import desugaring as ds
import desugaring/pipelines
import vxml.{Attr, Line, T, V}
import vxml/blame

pub fn main() {
  markdown_link_splitting_test()
}

fn markdown_link_splitting_test() {
  let input =
    V(blame.no_blame, "root", [], [
      T(blame.no_blame, [Line(blame.no_blame, "[label](target)")]),
    ])
  let pipeline = pipelines.markdown_link_splitting([], [])
  let assert Ok(#(output, _, _)) =
    ds.run_pipeline(input, pipeline, [], False, False)
  let assert V(
    _,
    "root",
    [],
    [T(_, [Line(_, "")]), V(_, "a", attrs, children), T(_, [Line(_, "")])],
  ) = output
  let assert [Attr(_, "href", "target")] = attrs
  let assert [T(_, [Line(_, "label")])] = children
}
