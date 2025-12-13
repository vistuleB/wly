import gleam/dict.{type Dict}
import gleam/float
import gleam/pair
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string.{inspect as ins}
import gleam/time/duration.{type Duration}
import gleam/time/timestamp.{type Timestamp}
import blame.{Ext, type Blame} as bl
import io_lines.{type InputLine, type OutputLine, OutputLine} as io_l
import desugarer_library as dl
import infrastructure.{type Desugarer, Pipe, type Pipeline, TrackingOff, TrackingForced, TrackingOnChange} as infra
import selector_library as sl
import shellout
import simplifile
import table_and_co_printer as pr
import vxml.{type VXML, V} as vp
import on
import input
import writerly as wp
import gleam/erlang/process.{type Subject, spawn, send, receive}
import dirtree.{type DirTree} as dt

// ************************************************************
// Assembler(a)                                                // 'a' is assembler error type; "assembler" = "source assembler"
// file/directory -> List(InputLine)
// ************************************************************

pub type Assembler(a) =
  fn(String) -> Result(#(List(InputLine), Option(DirTree)), a)    // the 'List(String)' is a feedback/success message on assembly

pub type AssemblerDebugOptions {
  AssemblerDebugOptions(echo_: Bool)
}

// 🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅
// 🌅 default assembler~~ 🌅
// 🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅

pub fn default_assembler(
  spotlight_paths: List(String),
) -> Assembler(wp.AssemblyError) {
  fn(input_dir) {
    use #(tree, assembled) <- on.ok(
      wp.assemble_input_lines_advanced_mode(input_dir, spotlight_paths),
    )
    Ok(#(assembled, Some(tree)))
  }
}

// unfinished: we also wanted 1 that chooses the shortname4u:
pub fn custom_shortname_assembler(
  shortname: String,
) -> Assembler(simplifile.FileError) {
  fn(path) {
    use string <- on.ok(
      simplifile.read(path)
    )
    Ok(#(
      io_l.string_to_input_lines(string, shortname, 0),
      None,
    ))
  }
}

// ************************************************************
// Paser(c)                                                    // 'c' is parser error type
// List(InputLine) -> VXML
// ************************************************************

pub type Parser(c) =
  fn(List(InputLine)) -> Result(VXML, #(Blame, c))

pub type ParserDebugOptions {
  ParserDebugOptions(echo_: Bool)
}

// 🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅
// 🌅 default Writerly parser~~~~ 🌅
// 🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅

pub fn default_writerly_parser(
  only_args: List(#(String, String, String)),
) -> Parser(String) {
  fn(lines) {
    use writerlys <- on.error_ok(
      wp.parse_input_lines(lines),
      fn(e) { Error(#(e.blame, ins(e))) },
    )

    use vxml <- on.ok(
      case writerlys |> wp.writerlys_to_vxmls {
        [vxml] -> Ok(vxml)
        vxmls -> Error(#(bl.no_blame, "found " <> ins(list.length(vxmls)) <> " ≠ 1 top-level nodes in writerly source"))
      }
    )

    use #(filtered_vxml, _) <- on.error_ok(
      dl.filter_nodes_by_attributes(only_args).transform(vxml),
      fn(_) { Error(#(bl.no_blame, "empty document after filtering nodes by: " <> ins(only_args))) },
    )

    Ok(filtered_vxml)
  }
}

// 🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅
// 🌅 default XML & HTML parser~~ 🌅
// 🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅

pub fn default_xml_parser(
  lines: List(InputLine),
  only_args: List(#(String, String, String)),
) -> Result(VXML, #(Blame, String)) {
  use vxml <- on.error_ok(
    vp.streaming_based_xml_parser(lines),
    fn(xmlm_parse_error) { Error(#(bl.no_blame, "xmlm parse error: " <> ins(xmlm_parse_error))) }
  )

  use #(vxml, _) <- on.error_ok(
    dl.filter_nodes_by_attributes(only_args).transform(vxml),
    fn(_) { Error(#(bl.no_blame, "empty document after filtering nodes by: " <> ins(only_args))) },
  )

  Ok(vxml)
}

pub const default_html_parser = default_xml_parser

// ************************************************************
// PipelineDebugOptions
// ************************************************************

const default_times_table_char_width = 90 // MacBook 16' can take 140

pub type PipelineDebugOptions {
  PipelineDebugOptions(
    times: Option(Int), // the 'Int' gives width of timing table
    interactive_mode: Bool,
  )
}

// ************************************************************
// Splitter(d, e)                                              // 'd' is fragment classifier type, 'e' is splitter error type
// VXML -> List(OutputFragment)
// ************************************************************

pub type OutputFragment(d, z) {                  // 'd' is fragment classifier type, 'z' is payload type (VXML or List(OutputLine))
  OutputFragment(classifier: d, path: String, payload: z)
}

pub type Splitter(d, e) =
  fn(VXML) -> Result(List(OutputFragment(d, VXML)), e)

pub type SplitterDebugOptions(d) {
  SplitterDebugOptions(echo_: fn(OutputFragment(d, VXML)) -> Bool)
}

// 🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅
// 🌅 stub splitter~~~~~~ 🌅
// 🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅

/// emits 1 fragment whose 'path' is the tag
/// of the VXML root concatenated with a provided
/// suffix, e.g., "<> Book" -> "Book.html"
pub fn stub_splitter(suffix: String) -> Splitter(Nil, Nil) {
  fn(root) {
    let assert V(_, tag, _, _) = root
    Ok([OutputFragment(classifier: Nil, path: tag <> suffix, payload: root)])
  }
}

// ************************************************************
// Emitter(d, f)                                               // where 'd' is fragment type & 'f' is emitter error type
// OutputFragment(d, VXML) -> OutputFragment(d, List(OutputLine))
// ************************************************************

pub type Emitter(d, f) =
  fn(OutputFragment(d, VXML)) -> Result(OutputFragment(d, List(OutputLine)), f)

pub type EmitterDebugOptions(d) {
  EmitterDebugOptions(
    echo_: fn(OutputFragment(d, List(OutputLine))) -> Bool,
  )
}

// 🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅
// 🌅 default Writerly emitter~~~ 🌅
// 🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅

pub fn default_writerly_emitter(
  fragment: OutputFragment(d, VXML),
) -> Result(OutputFragment(d, List(OutputLine)), b) {
  let lines =
    fragment.payload
    |> wp.vxml_to_writerlys
    |> list.map(wp.writerly_to_output_lines)
    |> list.flatten

  Ok(OutputFragment(..fragment, payload: lines))
}

// 🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅
// 🌅 stub HTML emitter~~ 🌅
// 🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅

pub fn stub_html_emitter(
  fragment: OutputFragment(d, VXML),
) -> Result(OutputFragment(d, List(OutputLine)), b) {
  let lines =
    list.flatten([
      [
        OutputLine(Ext([], "stub_html_emitter"), 0, "<!DOCTYPE html>"),
        OutputLine(Ext([], "stub_html_emitter"), 0, "<html>"),
        OutputLine(Ext([], "stub_html_emitter"), 0, "<head>"),
        OutputLine(Ext([], "stub_html_emitter"), 2, "<link rel=\"icon\" type=\"image/x-icon\" href=\"logo.png\">"),
        OutputLine(Ext([], "stub_html_emitter"), 2, "<meta charset=\"utf-8\">"),
        OutputLine(Ext([], "stub_html_emitter"), 2, "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">"),
        OutputLine(Ext([], "stub_html_emitter"), 2, "<script type=\"text/javascript\" src=\"./mathjax_setup.js\"></script>"),
        OutputLine(Ext([], "stub_html_emitter"), 2, "<script type=\"text/javascript\" id=\"MathJax-script\" async src=\"https://cdn.jsdelivr.net/npm/mathjax@3/es5/tex-svg.js\"></script>"),
        OutputLine(Ext([], "stub_html_emitter"), 0, "</head>"),
        OutputLine(Ext([], "stub_html_emitter"), 0, "<body>"),
      ],
      fragment.payload
        |> infra.v_get_children
        |> list.map(fn(vxml) { vp.vxml_to_html_output_lines(vxml, 2, 2) })
        |> list.flatten,
      [
        OutputLine(Ext([], "stub_html_emitter"), 0, "</body>"),
        OutputLine(Ext([], "stub_html_emitter"), 0, ""),
      ],
    ])
  Ok(OutputFragment(..fragment, payload: lines))
}

// 🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅
// 🌅 stub jsx emitter~~~ 🌅
// 🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅

pub fn stub_jsx_emitter(
  fragment: OutputFragment(d, VXML),
) -> Result(OutputFragment(d, List(OutputLine)), b) {
  let lines =
    list.flatten([
      [
        OutputLine(Ext([], "panel_emitter"), 0, "import Something from \"./Somewhere\";",),
        OutputLine(Ext([], "panel_emitter"), 0, ""),
        OutputLine(Ext([], "panel_emitter"), 0, "const OurSuperComponent = () => {"),
        OutputLine(Ext([], "panel_emitter"), 2, "return ("),
        OutputLine(Ext([], "panel_emitter"), 4, "<>"),
      ],
      vp.vxmls_to_jsx_output_lines(fragment.payload |> infra.v_get_children, 6, 2),
      [
        OutputLine(Ext([], "panel_emitter"), 4, "</>"),
        OutputLine(Ext([], "panel_emitter"), 2, ");"),
        OutputLine(Ext([], "panel_emitter"), 0, "};"),
        OutputLine(Ext([], "panel_emitter"), 0, ""),
        OutputLine(Ext([], "panel_emitter"), 0, "export default OurSuperComponent;"),
      ],
    ])
  Ok(OutputFragment(..fragment, payload: lines))
}

// ************************************************************
// Writer(d, g)                                                // 'd' is fragment classifier type, 'g' is writer error type
// String, OutputFragment(d, String) -> GhostOfOutputFragment(d)
// ************************************************************

pub type Writer(d, g) =
  fn(String, OutputFragment(d, String)) -> Result(GhostOfOutputFragment(d), g)

pub type WriterDebugOptions(d) {
  WriterDebugOptions(echo_: fn(OutputFragment(d, String)) -> Bool)
}

// 🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅
// 🌅 default writer~~~~~ 🌅
// 🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅

fn output_dir_local_path_printer(
  output_dir: String,
  local_path: String,
  content: String,
) -> Result(Nil, simplifile.FileError) {
  let assert False = string.starts_with(local_path, "/")
  let assert False = string.ends_with(output_dir, "/")
  let path = output_dir <> "/" <> local_path
  use _ <- on.ok(create_dirs_on_path_to_file(path))
  simplifile.write(path, content)
}

pub fn default_writer(
  output_dir: String,
  fragment: OutputFragment(d, String),
) -> Result(GhostOfOutputFragment(d), String) {
  case output_dir_local_path_printer(output_dir, fragment.path, fragment.payload) {
    Ok(Nil) -> {
      Ok(GhostOfOutputFragment(fragment.classifier, fragment.path))
    }
    Error(file_error) -> {
      Error(ins(file_error) <> " on path " <> output_dir <> "/" <> fragment.path)
    }
  }
}

// ************************************************************
// Prettifier(d, h)                                            // 'd' is fragment classifier, 'h' is prettifier error type
// String, GhostOfOutputFragment(d), Option(String) -> Result(String, h)
// ☝                                 ☝                        ☝
// output_dir                        optional                 on_success
//                                   'prettified dir'         report-back message
//                                   (else use output_dir)
// ************************************************************

pub type GhostOfOutputFragment(d) {
  GhostOfOutputFragment(classifier: d, path: String)
}

pub type Prettifier(d, h) =
  fn(String, GhostOfOutputFragment(d), Option(String)) -> Result(String, h)

pub type PrettifierDebugOptions(d) {
  PrettifierDebugOptions(echo_: fn(GhostOfOutputFragment(d)) -> Bool)
}

// 🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅
// 🌅 default prettifier~ 🌅
// 🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅

pub fn run_prettier(in: String, path: String, check: Bool) -> Result(String, #(Int, String)) {
  shellout.command(
    run: "prettier",
    in: in,
    with: [
      "",
      case check {
        True -> "--check"
        False -> "--write"
      },
      path
    ],
    opt: [],
  )
}

pub fn default_prettier_prettifier(
  output_dir: String,
  ghost: GhostOfOutputFragment(d),
  prettier_dir: Option(String),
) -> Result(String, #(Int, String)) {
  let source_path = output_dir <> "/" <> ghost.path
  case prettier_dir {
    Some(dir) -> {
      let dest_path = dir <> "/" <> ghost.path
      use _ <- on.error_ok(
        create_dirs_on_path_to_file(dest_path),
        fn(e) {Error(#(0, "error creating directories on path: " <> ins(e)))},
      )
      use _ <- on.ok(
        case source_path != dest_path {
          True -> shellout.command(run: "cp", in: ".", with: [source_path, dest_path], opt: [])
          False -> Ok("")
        }
      )
      run_prettier(".", dest_path, False)
      |> result.map(fn(_) {"prettified [" <> dir <> "/]" <> ghost.path})
    }
    None -> {
      run_prettier(".", source_path, True)
      |> result.map(fn(msg) {
        msg <> " for [" <> output_dir <> "/]" <> ghost.path
      })
    }
  }
}

// 🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅
// 🌅 empty prettifier~~~ 🌅
// 🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅🌅

pub fn empty_prettifier(
  _: String,
  _: GhostOfOutputFragment(d),
  _: Option(String)
) -> Result(String, #(Int, String)) {
  Ok("")
}

// ************************************************************
// Renderer(a, c, d, e, f, g, h)
// ************************************************************

pub type Renderer(
  a, // SourceAssembler error type
  c, // SourceParser error type
  d, // VXML Fragment enum type
  e, // Splitter error type
  f, // Emitter error type
  g, // Writer error type
  h, // Prettifier error type
) {
  Renderer(
    assembler: Assembler(a),             // file/directory -> List(InputLine)                                    Result w/ error type a
    parser: Parser(c),                   // List(InputLine) -> VXML                                              Result w/ error type c
    pipeline: Pipeline,                  // VXML -> ... -> VXML                                                  Result w/ error type InSituDesugaringError
    splitter: Splitter(d, e),            // VXML -> List(OutputFragment(d, VXML))                                Result w/ error type e
    emitter: Emitter(d, f),              // OutputFragment(d, VXML) -> OutputFragment(d, String)                 Result w/ error type f
    writer: Writer(d, g),                // output_dir, OutputFragment(d, String) -> GhostOfOutputFragment(d)    Result w/ error type g
    prettifier: Prettifier(d, h),        // output_dir, GhostOfOutputFragment(d), Option(prettifier_dir) -> Nil  Result w/ error type h
  )
}

// ************************************************************
// RendererParameters
// ************************************************************

pub type PrettifierMode {
  PrettifierOff
  PrettifierOverwriteOutputDir
  PrettifierToBespokeDir(String)
}

pub type RendererParameters {
  RendererParameters(
    table: Bool,
    input_dir: String,
    output_dir: String,
    prettifier_behavior: PrettifierMode,
    verbose: Bool,
    warnings: Bool,
  )
}

// ************************************************************
// RendererDebugOptions(d)                                     // 'd' is fragment classifier type
// ************************************************************

pub type RendererDebugOptions(d) {
  RendererDebugOptions(
    assembler_debug_options: AssemblerDebugOptions,
    parser_debug_options: ParserDebugOptions,
    pipeline_debug_options: PipelineDebugOptions,
    splitter_debug_options: SplitterDebugOptions(d),
    emitter_debug_options: EmitterDebugOptions(d),
    writer_debug_options: WriterDebugOptions(d),
    prettifier_debug_options: PrettifierDebugOptions(d),
  )
}

// ************************************************************
// empty (default) RendererDebugOptions
// ************************************************************

pub fn empty_assembler_debug_options() -> AssemblerDebugOptions {
  AssemblerDebugOptions(echo_: False)
}

pub fn empty_parser_debug_options() -> ParserDebugOptions {
  ParserDebugOptions(echo_: False)
}

pub fn empty_pipeline_debug_options() -> PipelineDebugOptions {
  PipelineDebugOptions(times: None, interactive_mode: False)
}

pub fn empty_splitter_debug_options() -> SplitterDebugOptions(d) {
  SplitterDebugOptions(echo_: fn(_fr) { False })
}

pub fn empty_emitter_debug_options() -> EmitterDebugOptions(d) {
  EmitterDebugOptions(echo_: fn(_fr) { False })
}

pub fn empty_writer_debug_options() -> WriterDebugOptions(d) {
  WriterDebugOptions(echo_: fn(_fr) { False })
}

pub fn empty_prettifier_debug_options() -> PrettifierDebugOptions(d) {
  PrettifierDebugOptions(echo_: fn(_fr) { False })
}

pub fn default_renderer_debug_options() -> RendererDebugOptions(d) {
  RendererDebugOptions(
    assembler_debug_options: empty_assembler_debug_options(),
    parser_debug_options: empty_parser_debug_options(),
    pipeline_debug_options: empty_pipeline_debug_options(),
    splitter_debug_options: empty_splitter_debug_options(),
    emitter_debug_options: empty_emitter_debug_options(),
    writer_debug_options: empty_writer_debug_options(),
    prettifier_debug_options: empty_prettifier_debug_options(),
  )
}

// ************************************************************
// CommandLineAmendments
// ************************************************************

pub type PipelineTrackingModifier {
  PipelineTrackingModifier(
    selector: Option(infra.Selector),
    steps_with_tracking_on_change: List(Int),
    steps_with_tracking_forced: List(Int),
    interactive_mode: Bool,
  )
}

pub type CommandLineAmendments {
  CommandLineAmendments(
    help: Bool,
    input_dir: Option(String),
    output_dir: Option(String),
    only_paths: List(String),
    only_key_values: List(#(String, String, String)),
    prettier: Option(PrettifierMode),
    track: Option(PipelineTrackingModifier),
    peek: Option(List(Int)),
    table: Option(Bool),
    times: Option(Int),
    verbose: Option(Bool),
    warnings: Option(Bool),
    timing: Option(Bool),
    echo_assembled: Bool,
    vxml_fragments_local_paths_to_echo: Option(List(String)),
    output_lines_fragments_local_paths_to_echo: Option(List(String)),
    printed_string_fragments_local_paths_to_echo: Option(List(String)),
    prettified_string_fragments_local_paths_to_echo: Option(List(String)),
    user_args: Dict(String, List(String)),
  )
}

// ************************************************************
// empty (default) CommandLineAmendments
// ************************************************************

pub fn empty_command_line_amendments() -> CommandLineAmendments {
  CommandLineAmendments(
    help: False,
    input_dir: None,
    output_dir: None,
    only_paths: [],
    only_key_values: [],
    prettier: None,
    track: None,
    peek: None,
    table: None,
    times: None,
    verbose: None,
    warnings: None,
    timing: None,
    echo_assembled: False,
    vxml_fragments_local_paths_to_echo: None,
    output_lines_fragments_local_paths_to_echo: None,
    printed_string_fragments_local_paths_to_echo: None,
    prettified_string_fragments_local_paths_to_echo: None,
    user_args: dict.from_list([]),
  )
}

// ************************************************************
// cli_usage
// ************************************************************

pub fn basic_cli_usage(header: String) {
  let margin = "   "
  case header {
    "" -> Nil
    _ -> io.println(header <> "\n")
  }
  io.println(margin <> "--help")
  io.println(margin <> "  -> print the basic command line options (this message)")
  io.println("")
  io.println(margin <> "--esoteric")
  io.println(margin <> "  -> print advanced command line options")
  io.println("")
  io.println(margin <> "--only <string1> <string2> ...")
  io.println(margin <> "  -> restrict source to files whose paths contain at least one of")
  io.println(margin <> "     the given strings as a substring")
  io.println("")
  io.println(margin <> "--only <key1=val1> <key2=val2> ...")
  io.println(margin <> "  -> restrict source to elements that have at least one of the")
  io.println(margin <> "     given key-value pairs as attrs (& ancestors of such)")
  io.println("")
  io.println(margin <> "--peek <step numbers>")
  io.println(margin <> "  -> show entire document at given pipeline step numbers; leave")
  io.println(margin <> "     step numbers empty to output document at all steps; use")
  io.println(margin <> "     negative indices to indicate steps from end of pipeline")
  io.println("")
  io.println(margin <> "--track <string> +<p>-<m> [<step numbers>]")
  io.println(margin <> "  -> track changes near the document fragment given by <string>,")
  io.println(margin <> "     that can refer to any part of the printed VXML output except")
  io.println(margin <> "     for leading whitespace; e.g.:")
  io.println("")
  io.println(margin <> "     gleam run -- --track \"lorem ipsum\"")
  io.println(margin <> "     gleam run -- --track src=img/23.svg")
  io.println(margin <> "     gleam run -- --track \"<> ImageRight\"")
  io.println("")
  io.println(margin <> "     • +<p>-<m>: track p lines beyond and m lines before <string>")
  io.println(margin <> "       e.g., '+15-5' to track 15 lines beyond and 5 lines before")
  io.println(margin <> "       lines where the marker appears")
  io.println("")
  io.println(margin <> "     • <step numbers> specificy which desugaring steps to track:")
  io.println(margin <> "         • <x-y> to track changes in desugaring steps x to y only")
  io.println(margin <> "         • !x to force a printout at step x")
  io.println("")
  io.println(margin <> "     leave <step numbers> empty to track all steps")
  io.println("")
  io.println(margin <> "  -> additional options for --track:")
  io.println("")
  io.println(margin <> "     • 'with-ancestors': trigger selection of ancestor tags of")
  io.println(margin <> "        selected lines")
  io.println(margin <> "     • 'with-elder-siblings': trigger selection of ancestor tags")
  io.println(margin <> "        and elder sibling tags of selected lines")
  io.println(margin <> "     • 'with-ancestor-attrs' | 'with-attrs': trigger selection of")
  io.println(margin <> "        ancestor tags of selected lines and their attributes")
  io.println(margin <> "     • 'with-elder-sibling-attrs': trigger selection of ancestor")
  io.println(margin <> "        tags and elder siblings tags of selected lines and their")
  io.println(margin <> "        attributes")
  io.println(margin <> "     • '-i': \"interactive mode\": pauses for user input after each")
  io.println(margin <> "        output; type 'enter' for next chunk, else:")
  io.println(margin <> "          • 'e' to escape the interactive mode;")
  io.println(margin <> "          • <n> to fast-forward past n next outputs;")
  io.println(margin <> "          • 'c' to cancel the desugaring entirely;")
  io.println("")
  io.println(margin <> "--prettier [<dir>]")
  io.println(margin <> "  -> turn the prettifier on and have the prettifier output to")
  io.println(margin <> "     <dir>; if absent, <dir> defaults to")
  io.println(margin <> "     renderer_parameters.output_dir")
  io.println("")
  io.println(margin <> "--verbose/--succinct")
  io.println(margin <> "  -> force/suppress verbose renderer output")
  io.println("")
  io.println(margin <> "--table/--no-table")
  io.println(margin <> "  -> include/exclude a printout of the pipeline steps")
  io.println("")
  io.println(margin <> "--times [<cols=" <> ins(default_times_table_char_width) <> ">]")
  io.println(margin <> "  -> include desugarer timing table using <cols> columns")
  io.println("")
}

pub fn advanced_cli_usage(header: String) {
  let margin = "   "
  case header {
    "" -> Nil
    _ -> io.println(header <> "\n")
  }
  io.println(margin <> "--warnings/--no-warnings")
  io.println(margin <> "  -> force/suppress long-form printout of desugaring warnings")
  io.println("")
  io.println(margin <> "--echo-assembled")
  io.println(margin <> "  -> print the assembled input lines of source")
  io.println("")
  io.println(margin <> "--echo-vxml-fragments <subpath1> <subpath2> ...")
  io.println(margin <> "  -> echo fragments whose paths contain one of the given subpaths")
  io.println(margin <> "     before conversion to output lines, list none to match all", )
  io.println("")
  io.println(margin <> "--echo-ol-fragments <subpath1> <subpath2> ...")
  io.println(margin <> "  -> echo fragments whose paths contain one of the given subpaths")
  io.println(margin <> "     after conversion to output lines, list none to match all", )
  io.println("")
  io.println(margin <> "--track-steps")
  io.println(margin <> "  -> (re)set the tracking step numbers of the current tracker, if")
  io.println(margin <> "     any; takes arguments in the same form as the <step numbers>")
  io.println(margin <> "     sub-option of '--track' (e.g., '50-60 !123-125 !-1')", )
  io.println("")
}

// ************************************************************
// process_command_line_arguments
// ************************************************************

pub type CommandLineError {
  ExpectedDoubleDashString(String)
  UknownOptionArgument(String)
  UnexpectedArgumentsToOption(String)
  MissingArgumentToOption(String)
  TooManyArgumentsToOption(String)
  SelectorValues(String)
  StepNoValues(String)
  TimesValues(String)
}

pub fn process_command_line_arguments(
  arguments: List(String),
  user_keys: List(String),
) -> Result(CommandLineAmendments, CommandLineError) {
  use list_key_values <- on.error_ok(
    double_dash_keys(arguments),
    fn(bad_key) { Error(ExpectedDoubleDashString(bad_key)) },
  )

  list_key_values
  |> list.fold(
    Ok(empty_command_line_amendments()),
    fn(
      result: Result(CommandLineAmendments, CommandLineError),
      pair: #(String, List(String)),
    ) {
      use amendments <- on.ok(result)
      let #(option, values) = pair
      case option {
        "--help" -> {
          basic_cli_usage("\nwly renderer common command line options:")
          case list.is_empty(values) {
            True -> Ok(CommandLineAmendments(..amendments, help: True))
            False -> Error(UnexpectedArgumentsToOption("option"))
          }
        }

        "--esoteric" -> {
          advanced_cli_usage("\nwly renderer advanced command line options:")
          case list.is_empty(values) {
            True -> Ok(CommandLineAmendments(..amendments, help: True))
            False -> Error(UnexpectedArgumentsToOption("option"))
          }
        }

        "--times" -> {
          use arg <- on.ok(
            parse_times_args(values)
          )
          Ok(CommandLineAmendments(..amendments, times: arg |> infra.with_default(default_times_table_char_width)))
        }

        "--input-dir" -> {
          case values {
            [one] -> Ok(CommandLineAmendments(..amendments, input_dir: Some(one)))
            [] -> Error(MissingArgumentToOption("--input-dir"))
            _ -> Error(TooManyArgumentsToOption("--input-dir"))
          }
        }

        "--output-dir" -> {
          case values {
            [one] -> Ok(CommandLineAmendments(..amendments, output_dir: Some(one)))
            [] -> Error(MissingArgumentToOption("--output-dir"))
            _ -> Error(TooManyArgumentsToOption("--output-dir"))
          }
        }

        "--only" -> {
          let args =
            values
            |> list.map(parse_attr_value_args_in_filename)
            |> list.flatten()

          CommandLineAmendments(..amendments, warnings: Some(option.unwrap(amendments.warnings, False)))
          |> amend_only_args(args)
          |> Ok
        }

        "--table" ->
          case list.is_empty(values) {
            True -> Ok(CommandLineAmendments(..amendments, table: Some(True)))
            False -> Error(UnexpectedArgumentsToOption("--table"))
          }

        "--no-table" ->
          case list.is_empty(values) {
            True -> Ok(CommandLineAmendments(..amendments, table: Some(False)))
            False -> Error(UnexpectedArgumentsToOption("--no-table"))
          }

        "--prettier" ->
          case values {
            [dir] -> Ok(CommandLineAmendments(..amendments, prettier: Some(PrettifierToBespokeDir(dir))))
            [] -> Ok(CommandLineAmendments(..amendments, prettier: Some(PrettifierOverwriteOutputDir)))
            _ -> Error(UnexpectedArgumentsToOption("--prettier2"))
          }

        "--track" -> {
          use pipeline_mod <- on.ok(parse_track_args(values))
          Ok(
            CommandLineAmendments(
              ..amendments,
              track: Some(join_pipeline_modifiers(
                amendments.track,
                pipeline_mod,
              )),
            ),
          )
        }

        "--track-steps" -> {
          use pipeline_mod <- on.ok(parse_track_steps_args(values))
          Ok(
            CommandLineAmendments(
              ..amendments,
              track: Some(join_pipeline_modifiers(
                amendments.track,
                pipeline_mod,
              )),
            ),
          )
        }

        "--peek" -> {
          use numbers <- on.ok(parse_peek_args(values))
          Ok(
            CommandLineAmendments(..amendments, peek: Some(numbers))
          )
        }

        "--echo-assembled" ->
          case list.is_empty(values) {
            True -> Ok(CommandLineAmendments(..amendments, echo_assembled: True))
            False -> Error(UnexpectedArgumentsToOption(option))
          }

        "--echo-vxml-fragments" ->
          case list.is_empty(values) {
            True -> Ok(CommandLineAmendments(..amendments, vxml_fragments_local_paths_to_echo: Some(values)))
            False -> Error(UnexpectedArgumentsToOption(option))
          }

        "--echo-ol-fragments" ->
          case list.is_empty(values) {
            True -> Ok(CommandLineAmendments(..amendments, output_lines_fragments_local_paths_to_echo: Some(values)))
            False -> Error(UnexpectedArgumentsToOption(option))
          }

        "--succinct" ->
          case list.is_empty(values) {
            True -> Ok(CommandLineAmendments(..amendments, verbose: Some(False)))
            False -> Error(UnexpectedArgumentsToOption(option))
          }
        
        "--verbose" ->
          case list.is_empty(values) {
            True -> Ok(CommandLineAmendments(..amendments, verbose: Some(True)))
            False -> Error(UnexpectedArgumentsToOption(option))
          }
        
        "--warnings" ->
          case list.is_empty(values) {
            True -> Ok(CommandLineAmendments(..amendments, warnings: Some(True)))
            False -> Error(UnexpectedArgumentsToOption(option))
          }
        
        "--no-warnings" ->
          case list.is_empty(values) {
            True -> Ok(CommandLineAmendments(..amendments, warnings: Some(False)))
            False -> Error(UnexpectedArgumentsToOption(option))
          }
        
        _ -> {
          case list.contains(user_keys, option) {
            True -> Ok(CommandLineAmendments(..amendments, user_args: dict.insert(amendments.user_args, option, values)))
            False -> Error(UknownOptionArgument(option))
          }
        }
      }
    },
  )
}

// 🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠
// process_command_line_arguments HELPERS no 1:
// getting the --keys & value lists 👇👇👇👇👇👇
// 🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠

fn take_strings_while_not_key(
  upcoming: List(String),
  bundled: List(String),
) -> #(List(String), List(String)) {
  case upcoming {
    [] -> #(bundled |> list.reverse, upcoming)
    [first, ..rest] -> {
      case string.starts_with(first, "--") {
        True -> #(bundled |> list.reverse, upcoming)
        False -> take_strings_while_not_key(rest, [first, ..bundled])
      }
    }
  }
}

fn double_dash_keys(
  arguments: List(String),
) -> Result(List(#(String, List(String))), String) {
  case arguments {
    [] -> Ok([])
    [first, ..rest] -> {
      case string.starts_with(first, "--") {
        False -> Error(first)
        True -> {
          let #(arg_values, rest) = take_strings_while_not_key(rest, [])
          case double_dash_keys(rest) {
            Error(e) -> Error(e)
            Ok(parsed) -> Ok([#(first, arg_values), ..parsed])
          }
        }
      }
    }
  }
}

// 🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠
// process_command_line_arguments HELPERS no 2:
// for --only 👇👇👇👇👇👇👇👇👇👇👇👇👇👇👇👇👇👇👇👇
// 🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠

fn amend_only_args(
  amendments: CommandLineAmendments,
  args: List(#(String, String, String)),
) -> CommandLineAmendments {
  CommandLineAmendments(
    ..amendments,
    only_key_values: list.append(
      amendments.only_key_values,
      args
      |> list.filter(fn(a) {a.1 != "" || a.2 != ""})
    ),
    only_paths: list.append(
      amendments.only_paths,
      args
        |> list.map(fn(a) {
          let #(path, _, _) = a
          path
        })
        |> list.filter(fn(p){p != ""})
    ),
  )
}

fn parse_attr_value_args_in_filename(
  path: String,
) -> List(#(String, String, String)) {
  let assert [path, ..args] = string.split(path, "&")
  case args {
    // did not contain '&':
    [] -> {
      case string.split_once(path, "=") {
        Ok(#(key, value)) -> [#("", key, value)]
        Error(Nil) -> [#(path, "", "")]
      }
    }
    // did contain '&'
    _ ->
      list.map(args, fn(arg) {
        let assert [key, value] = string.split(arg, "=")
        // <- this should be generating a CommandLineError instead of asserting
        #(path, key, value)
      })
  }
}

// 🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠
// process_command_line_arguments HELPERS no 3:
// for --track (& --track-steps) 👇👇👇👇👇👇👇👇
// 🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠

pub type PlusMinusRange {
  PlusMinusRange(plus: Int, minus: Int)
}

fn parse_plus_minus(s: String) -> Result(PlusMinusRange, Nil) {
  case string.starts_with(s, "+"), string.starts_with(s, "-") {
    True, _ -> {
      let s = string.drop_start(s, 1)
      case string.split_once(s, "-") {
        Ok(#(before, after)) -> {
          case int.parse(before), int.parse(after) {
            Ok(p), Ok(m) -> Ok(PlusMinusRange(plus: p, minus: m))
            _, _ -> Error(Nil)
          }
        }
        _ ->
          case int.parse(s) {
            Ok(p) -> Ok(PlusMinusRange(plus: p, minus: 0))
            _ -> Error(Nil)
          }
      }
    }

    _, True -> {
      let s = string.drop_start(s, 1)
      case string.split_once(s, "+") {
        Ok(#(before, after)) -> {
          case int.parse(before), int.parse(after) {
            Ok(m), Ok(p) -> Ok(PlusMinusRange(plus: p, minus: m))
            _, _ -> Error(Nil)
          }
        }
        _ ->
          case int.parse(s) {
            Ok(m) -> Ok(PlusMinusRange(plus: 0, minus: m))
            _ -> Error(Nil)
          }
      }
    }

    _, _ -> Error(Nil)
  }
}

fn lo_hi_ints(lo: Int, hi: Int) -> List(Int) {
  case lo < hi {
    True -> [lo, ..lo_hi_ints(lo + 1, hi)]
    False -> [lo]
  }
}

fn unique_ints(g: List(Int)) -> List(Int) {
  g
  |> list.sort(int.compare)
  |> list.unique
}

fn cleanup_step_numbers(
  restrict: List(Int),
  force: List(Int),
) -> #(List(Int), List(Int)) {
  let force = force |> unique_ints
  let restrict =
    restrict |> unique_ints |> list.filter(fn(x) { !list.contains(force, x) })
  #(restrict, force)
}

fn parse_step_numbers(
  values: List(String),
) -> Result(#(List(Int), List(Int)), CommandLineError) {
  use #(restrict, force) <- on.ok(
    list.try_fold(values, #([], []), fn(acc, val) {
      let original_val = val
      let #(forced, val) = case string.starts_with(val, "!") {
        True -> #(True, string.drop_start(val, 1))
        False -> #(False, val)
      }
      let #(first_val_negative, val) = case string.starts_with(val, "-") {
        True -> #(True, string.drop_start(val, 1))
        False -> #(False, val)
      }
      let multiply_first = fn(x: Int) {
        case first_val_negative {
          True -> -x
          False -> x
        }
      }
      use ints <- on.ok(case string.split_once(val, "-") {
        Ok(#(before, after)) ->
          case int.parse(before), int.parse(after) {
            Ok(lo), Ok(hi) -> Ok(lo_hi_ints(lo |> multiply_first, hi))
            _, _ ->
              Error(StepNoValues(
                "unable to parse '" <> original_val <> "' as integer range (1)",
              ))
          }
        Error(Nil) ->
          case int.parse(val) {
            Ok(guy) -> Ok([guy |> multiply_first])
            Error(Nil) ->
              Error(StepNoValues(
                "unable to parse '" <> original_val <> "' as integer range (2)",
              ))
          }
      })
      case forced {
        False -> Ok(#(list.append(acc.0, ints), acc.1))
        True -> Ok(#(acc.0, list.append(acc.1, ints)))
      }
    }),
  )
  Ok(cleanup_step_numbers(restrict, force))
}

fn parse_track_args(
  values: List(String),
) -> Result(PipelineTrackingModifier, CommandLineError) {
  use first_payload, values <- on.empty_nonempty(
    values,
    Error(SelectorValues("missing 1st argument")),
  )

  let assert True = first_payload != ""
  let selector = sl.verbatim(first_payload)

  let values = list.map(values, fn(v) { string.replace(v, "-with", "with") })

  let #(with_enter, values) = infra.delete(values, "-i")
  let #(with_ancestors, values) = infra.delete(values, "with-ancestors")
  let #(with_elder_siblings, values) = infra.delete(values, "with-elder-siblings")
  let #(with_attrs, values) = infra.delete(values, "with-attrs")
  let #(with_attrs_v2, values) = infra.delete(values, "with-attributes")
  let #(with_ancestor_attrs, values) = infra.delete(values, "with-ancestor-attrs")
  let #(with_ancestor_attrs_v2, values) = infra.delete(values, "with-ancestor-attributes")
  let #(with_elder_sibling_attrs, values) = infra.delete(values, "with-elder-sibling-attrs")
  let #(with_elder_sibling_attrs_v2, values) = infra.delete(values, "with-elder-sibling-attributes")

  let with_attrs = with_attrs || with_attrs_v2
  let with_elder_sibling_attrs = with_elder_sibling_attrs || with_elder_sibling_attrs_v2 || with_attrs
  let with_ancestor_attrs = with_ancestor_attrs || with_ancestor_attrs_v2 || with_elder_sibling_attrs
  let with_elder_siblings = with_elder_siblings || with_elder_sibling_attrs
  let with_ancestors = with_ancestors || with_elder_siblings || with_ancestor_attrs

  let selector = case with_ancestors {
    False -> selector
    True -> infra.extend_selector_to_ancestors(
      selector,
      with_elder_siblings,
      with_ancestor_attrs,
      with_elder_sibling_attrs,
    )
  }

  use second_payload, values <- on.empty_nonempty(
    values,
    Ok(
      PipelineTrackingModifier(
        selector: Some(selector),
        steps_with_tracking_on_change: [],
        steps_with_tracking_forced: [],
        interactive_mode: with_enter,
      ),
    ),
  )

  use plus_minus <- on.error_ok(
    parse_plus_minus(second_payload),
    fn(_) {
      Error(SelectorValues(
        "2nd argument to --track should have form +<p>-<m> or -<m>+<p> where p, m are integers [" <> second_payload <> "]",
      ))
    },
  )

  let selector =
    selector
    |> infra.extend_selector_up(plus_minus.minus)
    |> infra.extend_selector_down(plus_minus.plus)

  use #(restrict, force) <- on.ok(
    parse_step_numbers(values)
  )

  Ok(PipelineTrackingModifier(
    selector: Some(selector),
    steps_with_tracking_on_change: restrict,
    steps_with_tracking_forced: force,
    interactive_mode: with_enter,
  ))
}

fn parse_track_steps_args(
  values: List(String),
) -> Result(PipelineTrackingModifier, CommandLineError) {
  use #(restrict, force) <- on.ok(
    parse_step_numbers(values)
  )

  Ok(PipelineTrackingModifier(
    selector: None,
    steps_with_tracking_on_change: restrict,
    steps_with_tracking_forced: force,
    interactive_mode: False,
  ))
}

fn join_pipeline_modifiers(
  pm1: Option(PipelineTrackingModifier),
  pm2: PipelineTrackingModifier,
) -> PipelineTrackingModifier {
  use pm1 <- on.none_some(pm1, pm2)
  let #(restrict, force) =
    cleanup_step_numbers(
      list.append(pm1.steps_with_tracking_forced, pm2.steps_with_tracking_forced),
      list.append(
        pm1.steps_with_tracking_on_change,
        pm2.steps_with_tracking_on_change,
      ),
    )
  PipelineTrackingModifier(
    selector: case pm1.selector, pm2.selector {
      Some(s1), Some(s2) -> Some(infra.or_selectors(s1, s2))
      _, _ -> option.or(pm1.selector, pm2.selector)
    },
    steps_with_tracking_on_change: restrict,
    steps_with_tracking_forced: force,
    interactive_mode: {
      pm1.interactive_mode ||
      pm2.interactive_mode
    }
  )
}

fn parse_peek_args(
  values: List(String)
) {
  use #(restrict, force) <- on.ok(parse_step_numbers(values))
  list.append(restrict, force)
  |> unique_ints
  |> Ok
}

// 🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠
// process_command_line_arguments HELPERS no 4:
// parsing --times potential Int 👇👇👇👇👇👇
// 🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠🐠

fn parse_times_args(
  values: List(String)
) -> Result(Option(Int), CommandLineError) {
  case values {
    [] -> Ok(None)
    [x] -> {
      use x <- on.error_ok(
        int.parse(x),
        fn(_) { Error(TimesValues("could not parse --times argument '" <> x <> "' as integer")) }
      )
      let x = int.max(x, 1)
      Ok(Some(x))
    }
    _ -> Error(UnexpectedArgumentsToOption("--times"))
  }
}


// ************************************************************
// RendererParameters + CommandLineAmendments -> RendererParameters
// ************************************************************

pub fn amend_renderer_paramaters_by_command_line_amendments(
  parameters: RendererParameters,
  amendments: CommandLineAmendments,
) -> RendererParameters {
  RendererParameters(
    table: option.unwrap(amendments.table, parameters.table),
    input_dir: option.unwrap(amendments.input_dir, parameters.input_dir),
    output_dir: option.unwrap(amendments.output_dir, parameters.output_dir),
    prettifier_behavior: option.unwrap(amendments.prettier, parameters.prettifier_behavior),
    verbose: option.unwrap(amendments.verbose, parameters.verbose),
    warnings: option.unwrap(amendments.warnings, parameters.warnings),
  )
}

// ************************************************************
// RendererDebugOptions + CommandLineAmendments -> RendererDebugOptions
// ************************************************************

fn exists_match(
  z: Option(List(a)), // List(a) = list of things that might cause a match, left empty if we always want a match
  f: fn(a) -> Bool,   // match tester
) -> Bool {
  case z {
    None -> False
    Some([]) -> True
    Some(x) -> list.any(x, f)
  }
}

pub fn db_amend_assembler_debug_options(
  _options: AssemblerDebugOptions,
  amendments: CommandLineAmendments,
) -> AssemblerDebugOptions {
  AssemblerDebugOptions(
    echo_: amendments.echo_assembled,
  )
}

pub fn db_amend_pipeline_debug_options(
  options: PipelineDebugOptions,
  amendments: CommandLineAmendments,
) -> PipelineDebugOptions {
  PipelineDebugOptions(
    times: amendments.times,
    interactive_mode: case amendments.track {
      None -> options.interactive_mode
      Some(track) -> track.interactive_mode
    },
  )
}

pub fn db_amend_splitter_debug_options(
  previous: SplitterDebugOptions(d),
  amendments: CommandLineAmendments,
) -> SplitterDebugOptions(d) {
  SplitterDebugOptions(echo_: fn(fr: OutputFragment(d, VXML)) {
    previous.echo_(fr) ||
    exists_match(
      amendments.vxml_fragments_local_paths_to_echo,
      string.contains(fr.path, _),
    )
  })
}

pub fn db_amend_emitter_debug_options(
  previous: EmitterDebugOptions(d),
  amendments: CommandLineAmendments,
) -> EmitterDebugOptions(d) {
  EmitterDebugOptions(echo_: fn(fr: OutputFragment(d, List(OutputLine))) {
    previous.echo_(fr) ||
    exists_match(
      amendments.output_lines_fragments_local_paths_to_echo,
      string.contains(fr.path, _),
    )
  })
}

pub fn db_amend_printed_debug_options(
  previous: WriterDebugOptions(d),
  amendments: CommandLineAmendments,
) -> WriterDebugOptions(d) {
  WriterDebugOptions(fn(fr: OutputFragment(d, String)) {
    previous.echo_(fr) ||
    exists_match(
      amendments.printed_string_fragments_local_paths_to_echo,
      string.contains(fr.path, _),
    )
  })
}

pub fn db_amend_prettifier_debug_options(
  previous: PrettifierDebugOptions(d),
  amendments: CommandLineAmendments,
) -> PrettifierDebugOptions(d) {
  PrettifierDebugOptions(fn(fr: GhostOfOutputFragment(d)) {
    previous.echo_(fr) ||
    exists_match(
      amendments.prettified_string_fragments_local_paths_to_echo,
      string.contains(fr.path, _),
    )
  })
}

pub fn amend_renderer_by_command_line_amendments(
  renderer: Renderer(a, c, d, e, f, g, h),
  amendments: CommandLineAmendments,
) -> Renderer(a, c, d, e, f, g, h) {
  let pipeline =
    renderer.pipeline
    |> apply_pipeline_tracking_modifier(amendments.track)
    |> apply_peeking(amendments.peek)

  Renderer(
    ..renderer,
    pipeline: pipeline
  )
}

pub fn amend_renderer_debug_options_by_command_line_amendments(
  debug_options: RendererDebugOptions(d),
  amendments: CommandLineAmendments,
) -> RendererDebugOptions(d) {
  RendererDebugOptions(
    db_amend_assembler_debug_options(
      debug_options.assembler_debug_options,
      amendments,
    ),
    debug_options.parser_debug_options,
    db_amend_pipeline_debug_options(
      debug_options.pipeline_debug_options,
      amendments,
    ),
    db_amend_splitter_debug_options(
      debug_options.splitter_debug_options,
      amendments,
    ),
    db_amend_emitter_debug_options(
      debug_options.emitter_debug_options,
      amendments,
    ),
    db_amend_printed_debug_options(
      debug_options.writer_debug_options,
      amendments,
    ),
    db_amend_prettifier_debug_options(
      debug_options.prettifier_debug_options,
      amendments,
    ),
  )
}

fn apply_peeking(
  pipeline: Pipeline,
  mod: Option(List(Int)),
) -> Pipeline {
  use mod <- on.none_some(mod, pipeline)
  let num_steps = list.length(pipeline)
  let wraparound = fn(x: Int) {
    case x < 0 {
      True -> num_steps + x + 1
      False -> x
    }
  }
  let apply_to_all = mod == []
  let peek_steps = list.map(mod, wraparound)
  case apply_to_all {
    True -> list.map(
      pipeline,
      fn(pipe) { Pipe(..pipe, peek: True) }
    )
    False -> list.index_map(
      pipeline,
      fn(pipe, i) {
        let step_no = i + 1
        Pipe(..pipe, peek: list.contains(peek_steps, step_no) )
      }
    )
  }
}

// ************************************************************
// Pipeline + PipelineTrackingModifier -> Pipeline (used by above)
// ************************************************************

fn apply_pipeline_tracking_modifier(
  pipeline: Pipeline,
  mod: Option(PipelineTrackingModifier),
) -> Pipeline {
  use mod <- on.none_some(mod, pipeline)
  let num_steps = list.length(pipeline)
  let wraparound = fn(x: Int) {
    case x < 0 {
      True -> num_steps + x + 1
      False -> x
    }
  }
  let on_change_steps = list.map(mod.steps_with_tracking_on_change, wraparound)
  let force = list.map(mod.steps_with_tracking_forced, wraparound)
  let apply_to_all = on_change_steps == [] && force == []
  case apply_to_all {
    True -> {
      list.map(
        pipeline,
        fn(pipe) {
          Pipe(
            desugarer: pipe.desugarer,
            selector: option.unwrap(mod.selector, pipe.selector),
            tracking_mode: TrackingOnChange,
            peek: pipe.peek,
          )
        }
      )
    }
    False -> {
      list.index_map(pipeline, fn(pipe, i) {
        let step_no = i + 1
        let on_change = list.contains(on_change_steps, step_no)
        let forced = list.contains(force, step_no)
        let mode = case on_change, forced {
          _, True -> TrackingForced
          True, _ -> TrackingOnChange
          _, _ -> TrackingOff
        }
        Pipe(
          desugarer: pipe.desugarer,
          selector: option.unwrap(mod.selector, pipe.selector),
          tracking_mode: mode,
          peek: pipe.peek,
        )
      })
    }
  }
}

// ************************************************************
// run_pipeline
// ************************************************************

pub type UserExit {
  UserExit(step_no: Int)
}

pub type InSituDesugaringError {
  InSituDesugaringError(
    desugarer: Desugarer,
    step_no: Int,
    message: String,
    blame: Blame,
  )
}

pub type InSituDesugaringWarning {
  InSituDesugaringWarning(
    desugarer: Desugarer,
    step_no: Int,
    message: String,
    blame: Blame,
  )
}

type Message {
  ProducedString(List(String), Int)
  ProducerFinished(
    Result(
      #(
        VXML,
        List(InSituDesugaringWarning),
        List(Timestamp),
        List(#(Int, Timestamp)),
        List(String),
      ),
      InSituDesugaringError,
    ),
  )
}

fn producer(
  main_process_subject: Subject(Message),
  vxml: VXML,
  pipeline: Pipeline,
) -> Nil {
  let track_any = list.any(pipeline, fn(p) { p.tracking_mode != TrackingOff })
  let last_step = list.length(pipeline)

  let final =
    pipeline
    |> list.try_fold(
      #(vxml, [], [], [], 1, "", False, []),
      fn(acc, pipe) {
        let #(
          vxml,
          warnings,
          all_times,
          requested_times,
          step_no,
          last_tracking_output,
          got_arrow,
          lines,
        ) = acc

        let Pipe(desugarer, selector, mode, peek) = pipe
        let now = timestamp.system_time()
        let all_times = [now, ..all_times]

        let requested_times = case desugarer.name == "timer" {
          True -> [#(step_no, now), ..requested_times]
          False -> requested_times
        }

        let #(printed_arrow, lines) = case track_any && !got_arrow {
          True -> {
            #(True, ["    💠", ..lines])
          }
          False -> #(False, lines)
        }

        use #(vxml, new_warnings) <- on.error_ok(
          desugarer.transform(vxml),
          fn(error) {
            Error(InSituDesugaringError(
              desugarer: desugarer,
              step_no: step_no,
              blame: error.blame,
              message: error.message,
            ))
          }
        )

        let new_warnings = list.map(
          new_warnings,
          fn(warning) {
            InSituDesugaringWarning(
              desugarer: desugarer,
              step_no: step_no,
              blame: warning.blame,
              message: warning.message,
            )
          }
        )

        let #(selected_2_print, next_tracking_output) = case mode == TrackingOff && !peek {
          True -> #([], last_tracking_output)

          False -> {
            let selected_2_print =
              vxml
              |> infra.vxml_to_s_lines
              |> selector
            let next_tracking_output =
              selected_2_print
              |> infra.s_lines_table("", True, 0)
            let selected_2_print = case peek {
              True -> vxml |> infra.vxml_to_s_lines |> sl.all()
              False -> selected_2_print
            }
            #(selected_2_print, next_tracking_output)
          }
        }

        let must_print = 
          peek ||
          mode == TrackingForced ||
          { mode == TrackingOnChange && next_tracking_output != last_tracking_output }

        let #(got_arrow, lines) = case must_print {
          True -> {
            // list.each(
            //   pr.name_and_param_string_lines(desugarer, step_no),
            //   fn(s) { io.println("    " <> s) },
            // )
            let lines = infra.pour(
              pr.name_and_param_string_lines(desugarer, step_no, 4),
              lines,
            )
            // io.println("    💠")
            let lines = ["    💠", ..lines] 
            let lines = 
              selected_2_print
              |> infra.s_lines_table_lines("", False, 2)
              |> infra.pour(lines)
            send(main_process_subject, ProducedString(lines |> list.reverse, step_no))
            #(False, [])
          }

          False -> case printed_arrow && step_no < last_step {
            True -> {
              // io.println("    ⋮")
              let lines = ["    ⋮", ..lines]
              #(True, lines)
            }
            False -> #(True, lines)
          }
        }

        #(
          vxml,
          list.append(warnings, new_warnings),
          all_times,
          requested_times,
          step_no + 1,
          next_tracking_output,
          got_arrow,
          lines,
        )
        |> Ok
      }
    )
    |> result.map(fn(acc) { #(acc.0, acc.1, acc.2, acc.3, acc.7) })

  send(main_process_subject, ProducerFinished(final))
}

fn loop(
  subject: Subject(Message),
  countdown: Int, // pause for user only when countdown == 0
) -> Result(#(
    VXML,
    List(InSituDesugaringWarning),
    List(Timestamp),
    List(#(Int, Timestamp)),
  ),
  Result(
    UserExit,
    InSituDesugaringError,
  )
) {
  case receive(subject, within: 100000) {
    Ok(ProducedString(lines, step_no)) -> {
      io.print(lines |> string.join("\n"))
      io.print(" (@" <> ins(step_no) <> ") ")
      case countdown == 0 {
        False -> {
          io.println("")
          loop(subject, countdown - 1)
        }
        True -> case input.input("(↵|<n>|e|c) ") {
          Ok(msg) -> {
            let #(countdown, quit) = case int.parse(msg) {
              Ok(q) -> #(q, False)
              Error(_) -> case msg {
                "e" -> #(-1, False)
                "c" -> #(-1, True)
                _ -> #(1, False)
              }
            }
            case quit {
              True -> Error(Ok(UserExit(step_no)))
              False -> loop(subject, countdown - 1)
            }
          }
          Error(_) -> {
            panic as "error reading input"
          }
        }
      }
    }

    Ok(ProducerFinished(result)) -> {
      case result {
        Ok(#(
          vxml,
          in_situ_warnings,
          timestamps,
          indexed_timestamps,
          last_lines,
        )) -> {
          case last_lines != [] {
            True -> {
              io.print(last_lines |> string.join("\n"))
              io.println("")
            }
            False -> Nil
          }
          Ok(#(
            vxml,
            in_situ_warnings,
            timestamps,
            indexed_timestamps,
          ))
        }
        Error(error) -> Error(Error(error))
      }
    }

    Error(_) -> {
      io.println("Timeout while waiting for messages. Is the producer stuck?")
      panic
    }
  }
}

fn run_pipeline(
  vxml: VXML,
  pipeline: Pipeline,
  interactive_mode: Bool,
) -> Result(#(
    VXML,
    List(InSituDesugaringWarning),
    List(Timestamp),
    List(#(Int, Timestamp)),
  ),
  Result(
    UserExit,
    InSituDesugaringError,
  ),
) {
  let main_subject = process.new_subject()

  let producer_pid = spawn(fn() {
    producer(
      main_subject,
      vxml,
      pipeline,
    )
  })

  process.link(producer_pid)

  let countdown = case interactive_mode {
    True -> 0
    False -> -1
  }

  loop(main_subject, countdown)
}

// ************************************************************
// other run_renderer helpers
// ************************************************************

fn sanitize_output_dir(parameters: RendererParameters) -> RendererParameters {
  RendererParameters(
    ..parameters,
    output_dir: infra.drop_ending_slash(parameters.output_dir),
  )
}

fn create_dirs_on_path_to_file(path_to_file: String) -> Result(Nil, simplifile.FileError) {
  let pieces = path_to_file |> string.split("/")
  let pieces = infra.drop_last(pieces)
  list.try_fold(pieces, ".", fn(acc, piece) {
    let acc = acc <> "/" <> piece
    use exists <- on.ok(simplifile.is_directory(acc))
    use _ <- on.ok(
      case exists {
        True  -> Ok(Nil)
        False -> simplifile.create_directory(acc)
      }
    )
    Ok(acc)
  })
  |> result.map(fn(_) { Nil })
}

// ************************************************************
// run_renderer return type(s)
// ************************************************************

pub type ThreePossibilities(f, g, h) {
  P1(f)
  P2(g)
  P3(h)
}

pub type RendererError(a, c, e, f, g, h) {
  FileOrParseError(a)
  SourceParserError(Blame, c)
  PipelineError(InSituDesugaringError)
  UserExitError(Int)
  SplitterError(e)
  EmittingOrWritingOrPrettifyingErrors(List(ThreePossibilities(f, g, h)))
}

// ************************************************************
// run_renderer
// ************************************************************

fn durations(
  times: List(Timestamp)
) -> List(Duration) {
  case times {
    [] -> panic
    [_] -> []
    [t_later, t_earlier, ..rest] -> [
      timestamp.difference(t_earlier, t_later),
      ..durations([t_earlier, ..rest]),
    ]
  }
}

pub fn run_renderer(
  renderer: Renderer(a, c, d, e, f, g, h),
  parameters: RendererParameters,
  debug_options: RendererDebugOptions(d),
) -> Result(Nil, RendererError(a, c, e, f, g, h)) {
  let parameters = sanitize_output_dir(parameters)

  let RendererParameters(
    table,
    input_dir,
    output_dir,
    prettifier_mode,
    verbose,
    show_warnings,
  ) = parameters

  case table {
    True -> pr.print_pipeline(renderer.pipeline |> infra.pipeline_desugarers)
    False -> Nil
  }

  // 🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸
  // 🌸 assembling~ 🌸
  // 🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸

  io.println("• assembling...")

  use #(assembled, tree) <- on.error_ok(
    renderer.assembler(input_dir),
    fn(error_a) {
      io.println("\n  ...assembler error on input_dir " <> input_dir <> ":")
      [
        "",
        "  " <> ins(error_a),
        "",
      ]
      |> pr.boxed_error_announcer("💥", 2, #(1, 0))
      Error(FileOrParseError(error_a))
    },
  )

  case verbose, tree {
    True, Some(tree) -> {
      let spaces = 
        string.repeat(" ", string.length("  -> assembled "))

      list.index_map(
        tree |> dt.pretty_print,
        fn(line, i) {
          case i == 0 { True -> "  -> assembled " False -> spaces}
          <> line
        }
      )
      |> string.join("\n") |> io.println
    }
    _, _ -> Nil
  }

  case debug_options.assembler_debug_options.echo_ {
    False -> Nil
    True -> {
      assembled
      |> io_l.input_lines_table("",  2)
      |> io.println
    }
  }

  // 🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸
  // 🌸 parsing~~~~ 🌸
  // 🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸

  io.println("• parsing input lines to VXML...")

  use parsed: VXML <- on.error_ok(
    renderer.parser(assembled),
    on_error: fn(error) {
      let #(blame, c) = error
      let assert [first, ..rest] =
        pr.padded_error_paragraph(ins(c) |> pr.strip_quotes, 70, "            ")

      io.println("\n  ...parser error:")
      [
        [
          "            ",
          "  blame:    " <> pr.our_blame_digest(blame),
          "  message:  " <> first,
        ],
        rest,
        [
          "",
        ]
      ]
      |> list.flatten
      |> pr.boxed_error_announcer("💥", 2, #(1, 0))
      Error(SourceParserError(blame, c))
    },
  )

  // 🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸
  // 🌸 running pipeline~~~ 🌸
  // 🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸

  io.println("• starting pipeline...")
  let t0 = timestamp.system_time()

  use #(desugared, warnings, all_times, requested_times) <- on.error_ok(
    run_pipeline(
      parsed,
      renderer.pipeline,
      debug_options.pipeline_debug_options.interactive_mode,
    ),
    on_error: fn(e) {
      case e {
        Ok(UserExit(step_no)) -> {
          io.println("")
          io.println("user exit at step_no " <> ins(step_no))
          Error(UserExitError(step_no))
        }
        Error(e) -> {
          let assert [first, ..rest] =
            pr.padded_error_paragraph(e.message, 80, "                  ")
          io.println("\n  DesugaringError:")
          [
            [
              "                  ",
              "  thrown by:      " <> e.desugarer.name,
              "  pipeline step:  " <> ins(e.step_no),
              "  blame:          " <> pr.our_blame_digest(e.blame),
              "  message:        " <> first,
            ],
            rest,
            [
              ""
            ],
          ]
          |> list.flatten
          |> pr.boxed_error_announcer("💥", 2, #(1, 0))
          Error(PipelineError(e))
        } 
      }
    }
  )

  let t1 = timestamp.system_time()
  let seconds =
    timestamp.difference(t0, t1) |> duration.to_seconds |> float.to_precision(3)

  case debug_options.pipeline_debug_options.times {
    None -> {
      io.println("  ..ended pipeline (" <> ins(seconds) <> "s)")
    }
    Some(total_chars) -> {
      let all_times = [t1, ..all_times]
      let all_seconds = durations(all_times) |> list.map(duration.to_seconds) |> list.reverse
      let assert Ok(max_secs) = list.max(all_seconds, float.compare)
      let num_hundreth_seconds = float.round(float.ceiling(max_secs *. 100.0))
      let one_hundreth_seconds_num_bars = int.max(1, total_chars / num_hundreth_seconds)
      let scale =
        list.repeat(Nil, num_hundreth_seconds)
        |> list.map_fold(0.0, fn(x, _) { #(x +. 0.01, x) })
        |> pair.second
        |> list.map(fn(x) {
          let x = ins(x |> float.to_precision(2)) <> "s"
          let num_spaces = one_hundreth_seconds_num_bars - string.length(x)
          x <> string.repeat(" ", num_spaces)
        })
        |> string.join("")
      assert list.length(all_seconds) == list.length(renderer.pipeline)
      let bars = list.index_map(
        list.zip(renderer.pipeline, all_seconds),
        fn (pair, i) {
          let #(pipe, seconds) = pair
          let num_bars = float.round(seconds *. 100.0 *. int.to_float(one_hundreth_seconds_num_bars))
          #(ins(i + 1) <> ".", pipe.desugarer.name, pr.blocks(num_bars))
        }
      )
      pr.three_column_table([#("#.", "name", scale), ..bars])
      |> pr.print_lines_at_indent(2)
      io.println("  ...ended pipeline in " <> ins(seconds) <> "s")
    }
  }

  case requested_times {
    [] -> Nil
    _ -> {
      let requested_times = [#(list.length(renderer.pipeline), t1), ..requested_times]
      list.fold(requested_times |> list.reverse, #(0, t0), fn(acc, next) {
        let #(step0, t0) = acc
        let #(step1, t1) = next
        let seconds =
          timestamp.difference(t0, t1)
          |> duration.to_seconds
          |> float.to_precision(3)
        io.println("  steps " <> ins(step0) <> " to " <> ins(step1) <> ": " <> ins(seconds) <> "s")
        next
      })
      Nil
    }
  }

  // 🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸
  // 🌸 splitting~~ 🌸
  // 🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸

  io.println("• splitting...")

  use fragments <- on.error_ok(
    renderer.splitter(desugared),
    on_error: fn(error: e) {
      io.println("\n  ...splitter error:")
      pr.boxed_error_announcer(
        [
          "",
          "  " <> ins(error),
          "",
        ],
        "💥",
        2,
        #(1, 1)
      )
      Error(SplitterError(error))
    },
  )

  let prefix = "[" <> output_dir <> "/]"
  let fragments_types_and_paths_4_table =
    list.map(fragments, fn(fr) { #(ins(fr.classifier), prefix <> fr.path) })

  case verbose {
    False -> {
      io.println("  -> obtained " <> pr.how_many("fragment", "fragments", list.length(fragments)))
    }
    True -> {
      io.println("  -> obtained " <> pr.how_many("fragment", "fragments", list.length(fragments)) <> ":")
      [#("classifier", "path"), ..fragments_types_and_paths_4_table]
      |> pr.two_column_table
      |> pr.print_lines_at_indent(2)
    }
  }

  fragments
  |> list.each(fn(fr) {
    case debug_options.splitter_debug_options.echo_(fr) {
      False -> Nil
      True -> {
        fr.payload
        |> vp.vxml_to_output_lines
        |> io_l.output_lines_table("fr:" <> fr.path, 2)
        |> io.println
      }
    }
  })

  // 🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸
  // 🌸 emitting~~~ 🌸
  // 🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸

  io.print("• converting VXML fragments to List(OutputLine) fragments...")

  let fragments =
    fragments
    |> list.map(renderer.emitter)

  io.println("")

  fragments
  |> list.each(fn(result) {
    case result {
      Error(_) -> Nil
      Ok(fr) -> {
        case debug_options.emitter_debug_options.echo_(fr) {
          False -> Nil
          True -> {
            fr.payload
            |> io_l.output_lines_table("fr-ol:" <> fr.path, 2)
            |> io.println
          }
        }
      }
    }
  })

  let num_emitter_errors = list.fold(fragments, 0, fn(acc, fr) {
    case fr {
      Ok(_) -> acc
      _ -> acc + 1
    }
  })

  list.each(
    fragments,
    fn (fr) {
      use error <- on.ok_error(fr, fn(_){Nil})
      io.println("\n  emitter error:")
      pr.boxed_error_announcer(
        [
          "",
          "  " <> ins(error),
          "",
        ],
        "💥",
        2,
        #(1, 0)
      )
    }
  )

  case num_emitter_errors {
    0 -> Nil
    _ -> io.println("")
  }

  io.println("• converting List(OutputLine) fragments to String fragments...")

  let fragments = {
    fragments
    |> list.map(
      on.error_ok(
        _,
        fn(error) {
          Error(P1(error))
        },
        fn(fr) {
          Ok(OutputFragment(..fr, payload: io_l.output_lines_to_string(fr.payload)))
        },
      )
    )
  }

  // 🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸
  // 🌸 writing (to file)~~ 🌸
  // 🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸

  io.println("• writing String fragments to files...")

  fragments
  |> list.each(fn(result) {
    case result {
      Error(_) -> Nil
      Ok(fr) -> {
        case debug_options.writer_debug_options.echo_(fr) {
          False -> Nil
          True -> {
            let header = "────────────────── writer echo: " <> fr.path <> " ──────────────────"
            io.println(header)
            io.println(fr.payload)
            io.println(pr.dashes(string.length(header)))
            io.println("")
          }
        }
      }
    }
  })

  let #(count, fragments) =
    fragments
    |> list.map_fold(
      0,
      fn(acc, result) {
        use fr <- on.error_ok(
          result,
          fn(e) { #(acc, Error(e)) }
        )
        case renderer.writer(output_dir, fr) {
          Error(e) -> #(acc, Error(P2(e)))
          Ok(z) -> {
            case verbose {
              False -> Nil
              True -> io.println("  wrote [" <> output_dir <> "/]" <> fr.path)
            }
            #(acc + 1, Ok(z))
          }
        }
      }
    )

  case verbose {
    False -> io.println("  -> wrote " <> ins(count) <> " files")
    True -> Nil
  }

  // 🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸
  // 🌸 prettifying 🌸
  // 🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸

  case prettifier_mode != PrettifierOff {
    True -> io.println("• prettifying")
    False -> Nil
  }
  let fragments =
    fragments
    |> list.map(fn(result) {
      use fr <- on.ok(result)
      use <- on.true_false(prettifier_mode == PrettifierOff, result)
      let dest_dir = case prettifier_mode {
        PrettifierOff -> panic as "bug"
        PrettifierOverwriteOutputDir -> Some(output_dir)
        PrettifierToBespokeDir(dir) -> Some(dir)
      }
      case renderer.prettifier(output_dir, fr, dest_dir) {
        Error(e) -> {
          io.println("  prettifying error: " <> ins(e))
          Error(P3(e))
        }
        Ok(message) -> {
          io.println("  " <> message)
          result
        }
      }
    })

  fragments
  |> list.each(fn(result) {
    use fr <- on.error_ok(result, fn(_) { Nil })
    case debug_options.prettifier_debug_options.echo_(fr) {
      False -> Nil
      True -> {
        let path = output_dir <> "/" <> fr.path
        use file_contents <- on.error_ok(
          simplifile.read(path),
          fn(error) {
            io.println("")
            io.println(
              "could not read back printed file " <> path <> ":" <> ins(error),
            )
          },
        )
        io.println("")
        let header = "───────────── prettifier echo: " <> fr.path <> " ──────────────────"
        io.println(header)
        io.println(file_contents)
        io.println(pr.dashes(string.length(header)))
        io.println("")
      }
    }
  })

  // 🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨
  // 🚨 print warnings~~~~~ 🚨
  // 🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨

  case list.length(warnings) {
    0 -> Nil
    _ -> {
      case show_warnings {
        True ->
          io.println("\n👉 " <> pr.how_many("warning", "warnings", list.length(warnings)) <> ":")
        False ->
          io.println("\n[" <> pr.how_many("suppressed warning", "suppressed warnings", list.length(warnings)) <> " (use '--warnings' option to see)]")
      }
    }
  }

  case show_warnings {
    True -> 
      list.each(
        warnings,
        fn (w) {
          [
            "",
            "  from:           " <> w.desugarer.name <> " (desugarer)",
            "  pipeline step:  " <> ins(w.step_no),
            "  blame:          " <> bl.blame_digest(w.blame),
            "  message:        " <> w.message,
            "",
          ]
          |> pr.boxed_error_announcer("🚨", 2, #(1, 0))
        }
      )
    False ->
      Nil
  }

  let #(_, errors) = result.partition(fragments)

  case errors {
    [] -> Ok(Nil)
    _ -> {
      Error(EmittingOrWritingOrPrettifyingErrors(errors))
    }
  }
}
