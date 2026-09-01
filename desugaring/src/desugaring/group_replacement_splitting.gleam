import desugaring/core
import gleam/list
import gleam/regexp.{type Regexp}
import gleam/string.{inspect as ins}
import vxml.{type Line, type VXML, Attr, Line, T, V}
import vxml/blame.{type Blame} as bl

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

pub type RegexpReplacementSplitter {
  RegexpReplacementSplitter(
    re: Regexp,
    groups: List(RegexpGroupSourceAndInstruction),
  )
}

pub fn rrs_param_stringifier(rrs: RegexpReplacementSplitter) -> String {
  rrs.groups
  |> list.map(fn(g) { ins(g.source) <> " -> " <> ins(g.instruction) })
  |> core.list_string_stringifier
}

fn replacement_nodes(
  b: Blame,
  split: String,
  instruction: SplitReplacementInstruction,
) -> List(VXML) {
  case instruction {
    Trash -> []
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

fn rrs_splits_to_nodes(
  blame: Blame,
  splits: List(String),
  w: RegexpReplacementSplitter,
) -> List(VXML) {
  let num_groups = list.length(w.groups)
  let split_cycle_length = num_groups + 1
  let splits = case list.length(splits) % split_cycle_length {
    // Erlang's regexp splitter omits an empty final segment when the match
    // reaches the end of the string. Restore it so every match has the same
    // capture-group layout.
    0 -> list.append(splits, [""])
    1 -> splits
    _ -> panic as "unexpected regexp capture-group layout"
  }

  let reversed =
    list.index_fold(
      splits,
      #(blame, [], []),
      fn(
        acc: #(Blame, List(RegexpGroupSourceAndInstruction), List(VXML)),
        split,
        index,
      ) {
        let #(b, grps, reversed) = acc
        let mod_index = index % split_cycle_length - 1
        let #(instruction, grps) = case mod_index == -1 {
          True -> #(Keep, w.groups)
          False -> {
            let assert [group, ..grps] = grps
            #(group.instruction, grps)
          }
        }
        let vxmls = replacement_nodes(b, split, instruction)
        let reversed = core.pour(vxmls, reversed)
        let b = bl.advance(b, string.length(split))
        #(b, grps, reversed)
      },
    )
    |> core.triple_3rd

  reversed
  |> list.reverse
  |> core.last_to_first_concatenation
}

fn rrs_split_line(line: Line, w: RegexpReplacementSplitter) -> List(VXML) {
  case regexp.split(w.re, line.content) {
    [_] -> [T(line.blame, [line])]
    splits -> rrs_splits_to_nodes(line.blame, splits, w)
  }
}

// *****************
// Nodemap API
// *****************

pub fn rrs_split_node(vxml: VXML, re: RegexpReplacementSplitter) -> List(VXML) {
  case vxml {
    V(_, _, _, _) -> [vxml]
    T(_, lines) -> {
      lines
      |> list.map(rrs_split_line(_, re))
      |> list.flatten
      |> core.plain_concatenation_in_list
    }
  }
}

fn rrs_split_nodes(
  nodes: List(VXML),
  re: RegexpReplacementSplitter,
) -> List(VXML) {
  nodes
  |> list.map(rrs_split_node(_, re))
  |> list.flatten
}

pub fn rrs_split_node__batch(
  vxml: VXML,
  rules: List(RegexpReplacementSplitter),
) -> List(VXML) {
  list.fold(rules, [vxml], rrs_split_nodes)
}

// *****************
// RegexpReplacementSplitter constructor helpers API
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
) -> RegexpReplacementSplitter {
  // the (even-length) backslash run in front of the delimiter gets its own
  // capture group and is Kept, rather than being swallowed together with the
  // delimiter: that is what lets "\\_" keep its literal backslash while the
  // "_" still counts as a live delimiter
  let assert Ok(re) =
    { parenthesize(regex_prefix_to_make_unescaped) <> parenthesize(suffix) }
    |> regexp.from_string
  RegexpReplacementSplitter(re: re, groups: [
    RegexpGroupSourceAndInstruction(regex_prefix_to_make_unescaped, Keep),
    RegexpGroupSourceAndInstruction(suffix, instruction),
  ])
}

pub fn rr_splitter(
  re_string source: String,
  replacement instruction: SplitReplacementInstruction,
) -> RegexpReplacementSplitter {
  let assert Ok(re) = regexp.from_string(source |> parenthesize)
  let group = RegexpGroupSourceAndInstruction(source, instruction)
  RegexpReplacementSplitter(re: re, groups: [group])
}

pub fn rr_splitter_for_groups(
  pairs: List(#(String, SplitReplacementInstruction)),
) -> RegexpReplacementSplitter {
  let re_string =
    list.map(pairs, fn(p) { parenthesize(p.0) }) |> string.join("")
  let assert Ok(re) = regexp.from_string(re_string)
  let groups =
    list.map(pairs, fn(p) { RegexpGroupSourceAndInstruction(p.0, p.1) })
  RegexpReplacementSplitter(re: re, groups: groups)
}

// length of the run of backslashes at the very end of a string
fn trailing_backslash_run(s: String) -> Int {
  case string.ends_with(s, "\\") {
    False -> 0
    True -> 1 + trailing_backslash_run(string.drop_end(s, 1))
  }
}

pub fn remaining_unescaped_splits(
  splits: List(String),
  escaped_splitter_replacement e: String,
) -> List(String) {
  case splits {
    [] -> panic
    [_] -> splits
    [first, ..rest] -> {
      // the delimiter is escaped only if the backslash run in front of it
      // has ODD length: "\$" is escaped, but "\\$" is a literal backslash
      // followed by a LIVE delimiter
      case trailing_backslash_run(first) % 2 == 1 {
        False -> [first, ..remaining_unescaped_splits(rest, e)]
        True -> {
          let assert [second, ..rest] = remaining_unescaped_splits(rest, e)
          [{ first |> string.drop_end(1) } <> e <> second, ..rest]
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
    list.index_fold(splits, #(blame, []), fn(acc, split, index) {
      let #(b, reversed) = acc
      let this_instruction = case index % 2 == 0 {
        True -> Keep
        False -> instruction
      }
      let vxmls = replacement_nodes(b, split, this_instruction)
      let reversed = core.pour(vxmls, reversed)
      let b = bl.advance(b, string.length(split))
      #(b, reversed)
    })
    |> core.pair_2nd

  reversed
  |> list.reverse
  |> core.last_to_first_concatenation
}

fn naive_unescaped_split_line(
  line: Line,
  splitter: String,
  escaped_splitter_replacement e: String,
  replacement r: SplitReplacementInstruction,
) -> List(VXML) {
  case string.contains(line.content, splitter) {
    False -> [T(line.blame, [line])]
    True ->
      naive_unescaped_split_content(line.blame, line.content, splitter, e, r)
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
      |> core.plain_concatenation_in_list
    }
  }
}
