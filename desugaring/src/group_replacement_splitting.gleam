import gleam/list
import gleam/regexp.{type Regexp}
import gleam/string.{inspect as ins}
import infrastructure as infra
import vxml.{type Line, type VXML, Attr, Line, T, V}
import blame.{type Blame} as bl

pub type SplitReplacementInstruction {
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
    instruction: SplitReplacementInstruction,
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

fn replacement_nodes(
  b: Blame,
  split: String,
  instruction: SplitReplacementInstruction,
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

fn rrs_split_content(
  blame: Blame,
  content: String,
  w: RegexpReplacementerSplitter,
) -> List(VXML) {
  assert content != ""
  let splits = regexp.split(w.re, content)
  let num_groups = list.length(w.groups)
  let num_splits = list.length(splits)
  assert num_splits % { num_groups + 1} == 1

  let reversed =
    list.index_fold(
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
        let vxmls = replacement_nodes(b, split, instruction)
        let reversed = infra.pour(vxmls, reversed)
        let b = bl.advance(b, string.length(split))
        #(b, grps, reversed)
      }
    )
    |> infra.triple_3rd

  reversed
  |> list.reverse
  |> infra.last_to_first_concatenation
}

fn rrs_split_line(
  line: Line,
  w: RegexpReplacementerSplitter,
) -> List(VXML) {
  case regexp.check(w.re, line.content) {
    False -> [T(line.blame, [line])]
    True -> rrs_split_content(line.blame, line.content, w)
  }
}

// *****************
// Nodemap API
// *****************

pub fn rrs_split_node(
  vxml: VXML,
  re: RegexpReplacementerSplitter,
) -> List(VXML) {
  case vxml {
    V(_, _, _, _) -> [vxml]
    T(_, lines) -> {
      lines
      |> list.map(rrs_split_line(_, re))
      |> list.flatten
      |> infra.plain_concatenation_in_list
    }
  }
}

fn rrs_split_nodes(
  nodes: List(VXML),
  re: RegexpReplacementerSplitter,
) -> List(VXML) {
  nodes
  |> list.map(rrs_split_node(_, re))
  |> list.flatten
}

pub fn rrs_split_node__batch(
  vxml: VXML,
  rules: List(RegexpReplacementerSplitter),
) -> List(VXML) {
  list.fold(
    rules,
    [vxml],
    rrs_split_nodes,
  )
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

pub fn unescaped_suffix_rr_splitter(
  re_suffix suffix: String,
  replacement instruction: SplitReplacementInstruction,
) -> RegexpReplacementerSplitter {
  let string = suffix |> unescaped_suffix
  let assert Ok(re) = string |> parenthesize |> regexp.from_string
  RegexpReplacementerSplitter(
    re: re,
    groups: [RegexpGroupSourceAndInstruction(string, instruction)],
  )
}

pub fn rr_splitter(
  re_string source: String,
  replacement instruction: SplitReplacementInstruction,
) -> RegexpReplacementerSplitter {
  let assert Ok(re) = regexp.from_string(source |> parenthesize)
  let group = RegexpGroupSourceAndInstruction(source, instruction)
  RegexpReplacementerSplitter(re: re, groups: [group])
}

pub fn rr_splitter_for_groups(
  pairs: List(#(String, SplitReplacementInstruction)),
) -> RegexpReplacementerSplitter {
  let re_string = list.map(pairs, fn(p) { parenthesize(p.0) }) |> string.join("")
  let assert Ok(re) = regexp.from_string(re_string)
  let groups = list.map(pairs, fn(p) { RegexpGroupSourceAndInstruction(p.0, p.1) })
  RegexpReplacementerSplitter(re: re, groups: groups)
}

pub fn remaining_unescaped_splits(
  splits: List(String),
  escaped_splitter_replacement e: String,
) -> List(String) {
  case splits {
    [] -> panic
    [_] -> splits
    [first, ..rest] -> {
      case string.ends_with(first, "\\") {
        False -> [first, ..remaining_unescaped_splits(rest, e)]
        True -> {
          let assert [second, ..rest] = remaining_unescaped_splits(rest, e)
          [
            { first |> string.drop_end(1) } <> e <> second,
            ..rest
          ]
        }
      }
    }
  }
}

fn naive_unescaped_split_content(
  blame: Blame,
  content: String,
  splitter: String,
  escaped_splitter_replacement: String,
  instruction: SplitReplacementInstruction,
) -> List(VXML) {
  let splits =
    string.split(content, splitter)
    |> remaining_unescaped_splits(escaped_splitter_replacement)
    |> list.intersperse(splitter)

  let reversed =
    list.index_fold(
      splits,
      #(blame, []),
      fn(acc, split, index) {
        let #(b, reversed) = acc
        let this_instruction = case index % 2 == 0 {
          True -> Keep
          False -> instruction
        }
        let vxmls = replacement_nodes(b, split, this_instruction)
        let reversed = infra.pour(vxmls, reversed)
        let b = bl.advance(b, string.length(split))
        #(b, reversed)
      }
    )
    |> infra.pair_2nd

  reversed
  |> list.reverse
  |> infra.last_to_first_concatenation
}

fn naive_unescaped_split_line(
  line: Line,
  splitter: String,
  escaped_splitter_replacement e: String,
  replacement r: SplitReplacementInstruction,
) -> List(VXML) {
  case string.contains(line.content, splitter) {
    False -> [T(line.blame, [line])]
    True -> naive_unescaped_split_content(line.blame, line.content, splitter, e, r)
  }
}
// *****************
// naive_unescaped Nodemap API
// *****************

pub fn naive_unescaped_split_node(
  vxml: VXML,
  splitter: String,
  escaped_splitter_replacement e: String,
  replacement r: SplitReplacementInstruction,
) -> List(VXML) {
  case vxml {
    V(_, _, _, _) -> [vxml]
    T(_, lines) -> {
      lines
      |> list.map(naive_unescaped_split_line(_, splitter, e, r))
      |> list.flatten
      |> infra.plain_concatenation_in_list
    }
  }
}