import infrastructure.{type Selector, type SLine, type SLineSelectedStatus} as infra
import gleam/string

fn line_selector(
  line: SLine,
  s: String,
) -> SLineSelectedStatus {
  case string.contains(line.content, s) {
    True -> infra.OG
    _ -> infra.NotSelected
  }
}

pub fn selector(
  s: String,
) -> Selector {
  line_selector(_, s)
  |> infra.line_selector_to_selector()
}
