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

pub type RegexpWithGroupReplacementInstructions {
  RegexpWithGroupReplacementInstructions(
    re: Regexp,
    from: String,
    instructions: List(GroupReplacementInstruction),
  )
}

pub fn human_inspect(
  gri: RegexpWithGroupReplacementInstructions
) -> String {
  ins(gri.instructions) <> " " <> gri.from
}

pub fn split_content_with_replacement(
  blame: Blame,
  content: String,
  w: RegexpWithGroupReplacementInstructions,
) -> List(VXML) {
  use <- on.true_false(
    content == "",
    [T(blame, [Line(blame, content)])]
  )

  let splits = regexp.split(w.re, content)
  let num_groups = list.length(w.instructions)
  let num_matches: Int = { list.length(splits) - 1 } / { num_groups + 1 }
  let assert True = { num_matches * { num_groups + 1 } } + 1 == list.length(splits)

  let #(_, results) = infra.index_map_fold(
    splits,
    0, // <-- the 'acc' is the char_offset from start of content for next split
    fn(acc, split, index) {
      let mod_index = index % { num_groups + 1 } - 1
      let assert Ok(instruction) = case mod_index != -1 {
        True -> infra.get_at(w.instructions, mod_index)
        False -> Ok(Keep)
      }
      let b = bl.advance(blame, acc)
      let node_replacement = case instruction {
        Trash -> None
        Keep -> Some([T(b, [Line(b, split)])])
        DropLast -> Some([
          T(b, [Line(b, string.drop_end(split, 1))]),
        ])
        Tag(tag) -> Some([
          V(b, tag, [], []),
        ])
        TagWithSplitAsVal(tag, key) -> Some([
          V(b, tag, [Attr(b, key, split)], []),
        ])
        TagWithTextChild(tag) -> Some([
          V(b, tag, [], [T(b, [Line(b, split)])],
        )])
        TagAndText(tag, txt) -> Some([
          V(b, tag, [], []),
          T(b, [Line(b, txt)]),
        ])
        TextAndTag(tag, txt) -> Some([
          T(b, [Line(b, txt)]),
          V(b, tag, [], []),
        ])
      }
      let new_acc = acc + string.length(split)
      #(new_acc, node_replacement)
    }
  )

  results
  |> option.values
  |> list.flatten
  |> infra.last_to_first_concatenation
}

fn split_blamed_line_with_replacement(
  line: Line,
  w: RegexpWithGroupReplacementInstructions,
) -> List(VXML) {
  split_content_with_replacement(line.blame, line.content, w)
}

fn split_if_t_with_replacement_in_node(
  vxml: VXML,
  re: RegexpWithGroupReplacementInstructions,
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
  re: RegexpWithGroupReplacementInstructions,
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
  rules: List(RegexpWithGroupReplacementInstructions),
) -> List(VXML) {
  list.fold(
    rules,
    [vxml],
    split_if_t_with_replacement_in_nodes,
  )
}

pub fn split_if_t_with_replacement_nodemap(
  vxml: VXML,
  rule: RegexpWithGroupReplacementInstructions,
) -> List(VXML) {
  split_if_t_with_replacement_in_nodes([vxml], rule)
}

// *****************
// RegexpWithGroupReplacementInstructions constructor helpers API
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
) -> RegexpWithGroupReplacementInstructions {
  let string = 
    suffix
    |> unescaped_suffix
    |> parenthesize

  let assert Ok(re) = string |> regexp.from_string

  RegexpWithGroupReplacementInstructions(
    re: re,
    from: string,
    instructions: [Tag(tag)],
  )
}

pub fn for_groups(
  pairs: List(#(String, GroupReplacementInstruction)),
) -> RegexpWithGroupReplacementInstructions {
  let #(re_string, instructions) =
    list.map_fold(
      pairs,
      "",
      fn (acc, p) {
        #(acc <> parenthesize(p.0), p.1)
      }
    )
  let assert Ok(re) = regexp.from_string(re_string)
  RegexpWithGroupReplacementInstructions(
    re: re,
    from: re_string,
    instructions: instructions,
  )
}