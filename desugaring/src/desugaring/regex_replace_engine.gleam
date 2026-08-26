import desugaring/core.{type DesugaringError, DesugaringError}
import gleam/list
import gleam/regexp.{type Regexp}
import vxml.{type VXML, Line, T}
import vxml/blame as bl

pub type Rule =
  #(Regexp, String)

pub fn prepare(param: #(String, String)) -> Result(Rule, DesugaringError) {
  let #(pattern, replacement) = param
  case regexp.from_string(pattern) {
    Ok(compiled) -> Ok(#(compiled, replacement))
    Error(_) ->
      Error(DesugaringError(bl.no_blame, "Invalid regex: " <> pattern))
  }
}

pub fn prepare_batch(
  param: List(#(String, String)),
) -> Result(List(Rule), DesugaringError) {
  list.try_map(param, prepare)
}

pub fn nodemap(vxml: VXML, rule: Rule) -> VXML {
  nodemap_batch(vxml, [rule])
}

pub fn nodemap_batch(vxml: VXML, rules: List(Rule)) -> VXML {
  case vxml {
    T(_, lines) ->
      T(
        ..vxml,
        lines: list.map(lines, fn(line) {
          Line(
            ..line,
            content: list.fold(rules, line.content, fn(content, rule) {
              regexp.replace(rule.0, content, rule.1)
            }),
          )
        }),
      )
    _ -> vxml
  }
}
