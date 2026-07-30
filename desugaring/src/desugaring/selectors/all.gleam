import desugaring/core.{type Selector, type SLine, type SLineSelectedStatus} as core

fn line_selector(
  _line: SLine,
) -> SLineSelectedStatus {
  core.OG
}

pub fn selector() -> Selector {
  line_selector(_)
  |> core.line_selector_to_selector()
}
