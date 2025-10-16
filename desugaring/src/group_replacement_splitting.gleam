import gleam/list
import gleam/option.{None, Some}
import gleam/regexp.{type Regexp}
import gleam/string.{inspect as ins}
import infrastructure as infra
import vxml.{type Line, type VXML, Attr, Line, T, V}
import blame.{type Blame} as bl
import on

pub type GroupReplacementInstruction {
  Keep
  Trash
  DropLast
  Tag(String)
  TagWithSplitAsVal(String, String)
  TagWithTextChild(String)
  TagAndText(String, String)
  TextAndTag(String, String)
}

pub type RegexpGroupSourceAndInstruction {
  RegexpGroupSourceAndInstruction(
    source: String,
    instruction: GroupReplacementInstruction,
  )
}

pub type RegexpReplacementerSplitter {
  RegexpReplacementerSplitter(
    re: Regexp,
    groups: List(RegexpGroupSourceAndInstruction),
  )
}

pub fn rrs_param_stringifier(
  rrs: RegexpReplacementerSplitter
) -> String {
  rrs.groups
  |> list.map(fn(g) { ins(g.source) <> " -> " <> ins(g.instruction) })
  |> infra.list_string_stringifier
}

fn apply_instruction(
  b: Blame,
  split: String,
  instruction: GroupReplacementInstruction,
) -> List(VXML) {
  case instruction {
    Trash -> [
    ]
    Keep -> [
      T(b, [Line(b, split)]),
    ]
    DropLast -> [
      T(b, [Line(b, string.drop_end(split, 1))]),
    ]
    Tag(tag) -> [
      V(b, tag, [], []),
    ]
    TagWithSplitAsVal(tag, key) -> [
      V(b, tag, [Attr(b, key, split)], []),
    ]
    TagWithTextChild(tag) -> [
      V(b, tag, [], [T(b, [Line(b, split)])]),
    ]
    TagAndText(tag, txt) -> [
      V(b, tag, [], []),
      T(b, [Line(b, txt)]),
    ]
    TextAndTag(tag, txt) -> [
      T(b, [Line(b, txt)]),
      V(b, tag, [], []),
    ]
  }
}

pub fn split_content_with_replacement(
  blame: Blame,
  content: String,
  w: RegexpReplacementerSplitter,
) -> List(VXML) {
  let splits = regexp.split(w.re, content)
  let num_groups = list.length(w.groups)
  let num_matches = { list.length(splits) - 1 } / { num_groups + 1 }
  let assert True = { num_matches * { num_groups + 1 } } + 1 == list.length(splits)
  let #(_, _, reversed) = list.index_fold(
    splits,
    #(blame, [], []),
    fn(acc: #(Blame, List(RegexpGroupSourceAndInstruction), List(VXML)), split, index) {
      let #(b, grps, reversed) = acc
      let mod_index = index % { num_groups + 1 } - 1
      let #(instruction, grps) = case mod_index == -1 {
        True -> #(Keep, w.groups)
        False -> {
          let assert [group, ..grps] = grps
          #(group.instruction, grps)
        }
      }
      let vxmls = apply_instruction(b, split, instruction)
      let reversed = infra.pour(vxmls, reversed)
      let b = bl.advance(b, string.length(split))
      #(b, grps, reversed)
    }
  )

  reversed
  |> list.reverse
  |> infra.last_to_first_concatenation
}

fn split_blamed_line_with_replacement(
  line: Line,
  w: RegexpReplacementerSplitter,
) -> List(VXML) {
  case regexp.check(w.re, line.content) {
    False -> [T(line.blame, [line])]
    True -> split_content_with_replacement(line.blame, line.content, w)
  }
}

fn split_if_t_with_replacement_in_node(
  vxml: VXML,
  re: RegexpReplacementerSplitter,
) -> List(VXML) {
  case vxml {
    V(_, _, _, _) -> [vxml]
    T(_, lines) -> {
      lines
      |> list.map(split_blamed_line_with_replacement(_, re))
      |> list.flatten
      |> infra.plain_concatenation_in_list
    }
  }
}

fn split_if_t_with_replacement_in_nodes(
  nodes: List(VXML),
  re: RegexpReplacementerSplitter,
) -> List(VXML) {
  nodes
  |> list.map(split_if_t_with_replacement_in_node(_, re))
  |> list.flatten
}

// *****************
// nodemap API
// *****************

pub fn split_if_t_with_replacement_nodemap__batch(
  vxml: VXML,
  rules: List(RegexpReplacementerSplitter),
) -> List(VXML) {
  list.fold(
    rules,
    [vxml],
    split_if_t_with_replacement_in_nodes,
  )
}

pub fn split_if_t_with_replacement_nodemap(
  vxml: VXML,
  rule: RegexpReplacementerSplitter,
) -> List(VXML) {
  split_if_t_with_replacement_in_nodes([vxml], rule)
}

// *****************
// RegexpReplacementerSplitter constructor helpers API
// *****************

pub const regex_prefix_to_make_unescaped = "(?<!\\\\)(?:(?:\\\\\\\\)*)"

pub fn unescaped_suffix(suffix: String) -> String {
  regex_prefix_to_make_unescaped <> "(?:" <> suffix <> ")"
}

pub fn parenthesize(s: String) -> String {
  "(" <> s <> ")"
}

pub fn unescaped_suffix_replacement_splitter(
  suffix: String,
  tag: String,
) -> RegexpReplacementerSplitter {
  let string = 
    suffix
    |> unescaped_suffix

  let assert Ok(re) = string |> parenthesize |> regexp.from_string

  RegexpReplacementerSplitter(
    re: re,
    groups: [RegexpGroupSourceAndInstruction(string, Tag(tag))],
  )
}

pub fn for_groups(
  pairs: List(#(String, GroupReplacementInstruction)),
) -> RegexpReplacementerSplitter {
  let re_string = list.map(pairs, fn(p) { parenthesize(p.0) }) |> string.join("")
  let assert Ok(re) = regexp.from_string(re_string)
  let groups = list.map(pairs, fn(p) { RegexpGroupSourceAndInstruction(p.0, p.1) })
  RegexpReplacementerSplitter(re: re, groups: groups)
}