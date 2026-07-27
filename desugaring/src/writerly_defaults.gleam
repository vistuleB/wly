import blame.{type Blame}
import desugaring.{type OutputFragment, type RendererOptions, OutputFragment}
import dirtree.{type DirTree}
import gleam/list
import gleam/option.{type Option, Some}
import gleam/result
import gleam/string.{inspect as ins}
import io_lines.{type InputLine, type OutputLine}
import vxml.{type VXML}
import writerly as wl

/// Transitional Writerly adapter defaults for the generic renderer.
///
/// This module keeps Writerly-specific assembly, parsing, and emitting
/// separate from the input-format-agnostic renderer core. It is adapter glue,
/// not core renderer API.
pub fn default_writerly_assembler(
  dirpath_or_filepath: String,
  options: RendererOptions(_),
) -> Result(#(List(InputLine), Option(DirTree)), wl.AssemblyError) {
  let path_selector = wl.path_selector_from_only_paths(options.only_paths)
  use #(tree, assembled) <- result.try(
    wl.assemble_input_lines_with_path_selector(dirpath_or_filepath, path_selector),
  )
  Ok(#(assembled, Some(tree)))
}

pub fn default_writerly_parser(
  lines: List(InputLine),
) -> Result(VXML, #(Blame, String)) {
  wl.input_lines_to_vxml(lines)
  |> result.map_error(fn(e) { #(e.blame, ins(e)) })
}

pub fn default_writerly_emitter(
  fragment: OutputFragment(z, VXML),
) -> Result(OutputFragment(z, List(OutputLine)), b) {
  let lines =
    fragment.payload
    |> wl.vxml_to_writerlys
    |> list.map(wl.writerly_to_output_lines)
    |> list.flatten

  Ok(OutputFragment(..fragment, payload: lines))
}
