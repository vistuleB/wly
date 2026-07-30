import desugaring/core.{type Selector, type SLine, type SLineSelectedStatus} as core
import gleam/string

fn line_selector(
  line: SLine,
  s: String,
) -> SLineSelectedStatus {
  case string.contains(line.content, s) {
    True -> core.OG
    _ -> core.NotSelected
  }
}

pub fn selector(
  s: String,
) -> Selector {
  line_selector(_, s)
  |> core.line_selector_to_selector()
}
