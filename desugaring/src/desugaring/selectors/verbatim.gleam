import desugaring/core.{type SelectionStatus, type Selector, type SLine} as core
import gleam/string

fn line_selector(
  line: SLine,
  s: String,
) -> SelectionStatus {
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
