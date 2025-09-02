import gleam/list
import gleam/option.{None, Some}
import gleam/regexp.{type Regexp}
import gleam/string.{inspect as ins}
import infrastructure as infra
import vxml.{type TextLine, type VXML, Attribute, TextLine, T, V}
import blame.{type Blame} as bl
import on

pub type GroupReplacementInstruction {
  Keep
  Trash
  DropLast
  Tag(String)
  TagWithAttribute(String, String)
  TagWithTextChild(String)
  TagFwdText(String, String)
  TagBwdText(String, String)
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
    [T(blame, [TextLine(blame, content)])]
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
      let updated_blame = bl.advance(blame, acc)
      let node_replacement = case instruction {
        Trash -> None
        Keep -> Some([T(updated_blame, [TextLine(updated_blame, split)])])
        DropLast -> Some([T(updated_blame, [TextLine(updated_blame, string.drop_end(split, 1))])])
        Tag(tag) -> Some([V(updated_blame, tag, [], [])])
        TagWithAttribute(tag, key) -> Some([V(
          updated_blame,
          tag,
          [Attribute(updated_blame, key, split)],
          [],
        )])
        TagWithTextChild(tag) -> Some([V(
          updated_blame,
          tag,
          [],
          [T(updated_blame, [TextLine(updated_blame, split)])],
        )])
        TagFwdText(tag, txt) -> Some([
          V(updated_blame, tag, [], []),
          T(updated_blame, [TextLine(updated_blame, txt)]),
        ])
        TagBwdText(tag, txt) -> Some([
          T(updated_blame, [TextLine(updated_blame, txt)]),
          V(updated_blame, tag, [], []),
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
  line: TextLine,
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

pub fn group(s: String) -> String {
  "(" <> s <> ")"
}

pub fn unescaped_suffix_replacement_splitter(
  suffix: String,
  tag: String,
) -> RegexpWithGroupReplacementInstructions {
  let string = 
    suffix
    |> unescaped_suffix
    |> group

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
        #(acc <> group(p.0), p.1)
      }
    )
  let assert Ok(re) = regexp.from_string(re_string)
  RegexpWithGroupReplacementInstructions(
    re: re,
    from: re_string,
    instructions: instructions,
  )
}