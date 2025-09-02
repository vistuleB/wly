import infrastructure.{type Selector, type SLine, type SLineSelectedStatus} as infra

fn line_selector(
  _line: SLine,
) -> SLineSelectedStatus {
  infra.OG
}

pub fn selector() -> Selector {
  line_selector(_)
  |> infra.line_selector_to_selector()
}
