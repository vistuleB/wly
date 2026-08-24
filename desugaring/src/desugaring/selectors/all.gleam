import desugaring/core.{type SelectionStatus, type Selector, type SLine} as core

fn line_selector(
  _line: SLine,
) -> SelectionStatus {
  core.OG
}

pub fn selector() -> Selector {
  line_selector(_)
  |> core.line_selector_to_selector()
}
