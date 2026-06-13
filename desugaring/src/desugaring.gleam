import gleam/function
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
import gleam/time/timestamp
import blame.{Ext, type Blame} as bl
import io_lines.{type InputLine, type OutputLine, OutputLine} as io_l
import desugarer_library as dl
import infrastructure.{type Desugarer, type Pipeline, type Selector} as infra
import selector_library as sl
import shellout
import simplifile
import table_and_co_printer as pr
import vxml.{type VXML, V} as vp
import on
import input
import writerly as wl
import gleam/erlang/process.{type Subject, spawn, send, receive}
import dirtree.{type DirTree} as dt
import gleam/regexp
import splitter

const default_times_table_char_width = 90 // MacBook 16' can take 140

pub type TrackingMode {
  TrackingOff
  TrackingOnChange
  TrackingForced
}

pub type DecoratedDesugarer {
  DecoratedDesugarer(
    desugarer: Desugarer,
    selector: Selector,
    tracking_mode: TrackingMode,
    dump: Bool,
  )
}

pub fn desugarers_2_decorateds(
  desugarers: List(Desugarer),
) -> List(DecoratedDesugarer) {
  desugarers
  |> list.map(fn (d) {
    DecoratedDesugarer(
      desugarer: d,
      selector: function.identity,
      tracking_mode: TrackingOff,
      dump: False,
    )
  })
}

// ************************************************************
// Assembler(a)                                                // 'a' is assembler error type; "assembler" = "source assembler"
// file/directory -> List(InputLine)
// ************************************************************

pub type Assembler(a) =
  fn(String) -> Result(#(List(InputLine), Option(DirTree)), a)    // the 'List(String)' is a feedback/success message on assembly

pub fn default_writerly_assembler(
  dirpath_or_filepath: String,
  options: RendererOptions(_),
) -> Result(#(List(InputLine), Option(DirTree)), wl.AssemblyError) {
  let only_paths = options.only_paths
  let #(s1, s2) = list.partition(only_paths, string.starts_with(_, "!"))
  let s1 = list.map(s1, string.drop_start(_, 1))
  let path_selector = case s1, s2 {
    [], [] -> fn(_) { True }
    [], _ -> fn(path) { list.any(s2, string.contains(path, _)) }
    _, [] -> fn(path) { !list.any(s1, string.contains(path, _)) }
    _, _ -> fn(path) { list.any(s2, string.contains(path, _)) && !list.any(s1, string.contains(path, _)) }
  }
  use #(tree, assembled) <- on.ok(
    wl.assemble_input_lines_with_path_selector(dirpath_or_filepath, path_selector),
  )
  Ok(#(assembled, Some(tree)))
}

pub fn default_other_files_assembler(
  path: String
) -> Result(#(List(InputLine), Option(DirTree)), simplifile.FileError) {
  io_l.read(path, 0)
  |> result.map(fn(lines) { #(lines, None) })
}

// ************************************************************
// Parser(b)                                                   // 'b' is parser error type
// List(InputLine) -> VXML
// ************************************************************

pub type Parser(b) =
  fn(List(InputLine)) -> Result(VXML, #(Blame, b))

pub fn default_writerly_parser(
  lines: List(InputLine)
) -> Result(VXML, #(Blame, String)) {
  wl.input_lines_to_vxml(lines)
  |> result.map_error(fn(e) { #(e.blame, ins(e)) })
}

pub fn default_xml_parser(
  lines: List(InputLine),
) -> Result(VXML, #(Blame, String)) {
  vp.streaming_based_xml_parser(lines)
  |> result.map_error(fn(e) { #(bl.no_blame, "xmlm parse error: " <> ins(e)) })
}

pub const default_html_parser = default_xml_parser

// ************************************************************
// Filterer(c)                                                 // 'c' is parser error type
// VXML -> VXML
// ************************************************************

pub type Filterer(c) =
  fn(VXML) -> Result(VXML, c)

pub fn default_filterer(
  vxml: VXML,
  options: RendererOptions(_),
  saving: List(String),
) -> Result(VXML, String) {
  use #(vxml, warnings) <- on.error_ok(
    dl.filter_nodes_by_path_key_values_while_saving(#(options.only_path_key_vals, saving)).transform(vxml),
    fn(e) { Error(e.message) }
  )
  assert warnings == []
  use #(vxml, warnings) <- on.error_ok(
    dl.filter_nodes_by_key_values_while_saving(#(options.only_key_vals, saving)).transform(vxml),
    fn(e) { Error(e.message) }
  )
  assert warnings == []
  Ok(vxml)
}

// ************************************************************
// Splitter(z, d)                                              // 'z' is fragment classifier type, 'd' is splitter error type
// VXML -> List(OutputFragment)
// ************************************************************

pub type OutputFragment(z, p) {                  // 'z' is fragment classifier type, 'p' is payload type (VXML or List(OutputLine))
  OutputFragment(classifier: z, path: String, payload: p)
}

pub type Splitter(z, d) =
  fn(VXML) -> Result(List(OutputFragment(z, VXML)), d)

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
// Emitter(z, e)                                               // where 'z' is fragment type & 'e' is emitter error type
// OutputFragment(z, VXML) -> OutputFragment(z, List(OutputLine))
// ************************************************************

pub type Emitter(z, e) =
  fn(OutputFragment(z, VXML)) -> Result(OutputFragment(z, List(OutputLine)), e)

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

pub fn stub_html_emitter(
  fragment: OutputFragment(z, VXML),
) -> Result(OutputFragment(z, List(OutputLine)), b) {
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

pub fn stub_jsx_emitter(
  fragment: OutputFragment(z, VXML),
) -> Result(OutputFragment(z, List(OutputLine)), b) {
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
// Writer(z, f)                                                // 'z' is fragment classifier type, 'f' is writer error type
// String, OutputFragment(z, String) -> GhostOfOutputFragment(z)
// ************************************************************

pub type Writer(z, f) =
  fn(String, OutputFragment(z, String)) -> Result(GhostOfOutputFragment(z), f)

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
  fragment: OutputFragment(z, String),
) -> Result(GhostOfOutputFragment(z), String) {
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
// PrettifierFeedback, Prettifier(z)
// ************************************************************

pub type GhostOfOutputFragment(z) {
  GhostOfOutputFragment(classifier: z, path: String)
}

pub type PrettifierFeedback {
  PrettifierFeedback(warnings: List(String), errors: List(String))
}

pub type Prettifier(z) =
  fn(String, GhostOfOutputFragment(z), Option(String)) -> Option(PrettifierFeedback)

pub fn run_prettier(in: String, path: String, check: Bool) -> PrettifierFeedback {
  let result = shellout.command(
    run: "prettier",
    in: in,
    with: [
      case check {
        True -> "--check"
        False -> "--write"
      },
      path
    ],
    opt: [],
  )
  let output = case result {
    Ok(s) -> s
    Error(#(_, s)) -> s
  }
  let lines = string.split(output, "\n")
  let warnings =
    lines
    |> list.filter(fn(l) { string.starts_with(l, "[warn]") })
    |> list.map(fn (s) { string.drop_start(s, 6) |> string.trim })
  let error_lines =
    lines
    |> list.filter(fn(l) { string.starts_with(l, "[error]") })
    |> list.map(fn (s) { string.drop_start(s, 7) |> string.trim })
  let errors = case result {
    Ok(_) -> error_lines
    Error(#(_, _)) ->
      case error_lines {
        [_, ..] -> error_lines
        [] -> {
          case check {
            True -> []
            False ->
              case string.trim(output) {
                "" -> []
                s -> [s]
              }
          }
        }
      }
  }
  PrettifierFeedback(warnings: warnings, errors: errors)
}

pub fn default_prettier_prettifier(
  output_dir: String,
  ghost: GhostOfOutputFragment(z),
  prettier_dir: Option(String),
) -> Option(PrettifierFeedback) {
  use <- on.eager_false_true(
    list.any([".html", ".tsx"], string.ends_with(ghost.path, _)),
    None
  )

  let source_path = output_dir <> "/" <> ghost.path

  use #(dest_path, check) <- on.stay(
    case prettier_dir {
      None -> on.Stay(#(source_path, True))

      Some(dir) -> {
        let dest_path = dir <> "/" <> ghost.path
        use <- on.true_false(
          source_path == dest_path,
          fn() { on.Stay(#(dest_path, False)) }
        )
        use _ <- on.error_ok(
          create_dirs_on_path_to_file(dest_path),
          fn(e) {
            on.Return(Some(PrettifierFeedback(
              warnings: [],
              errors: ["could not create directories on path " <> ins(e)]
            )))
          }
        )
        case shellout.command(
          run: "cp",
          in: ".",
          with: [source_path, dest_path],
          opt: [],
        ) {
          Error(#(_, msg)) -> {
            on.Return(Some(PrettifierFeedback(
              warnings: [],
              errors: ["unable to copy '" <> source_path <> "' to '" <> dest_path <> "':" <> string.trim(msg)])
            ))
          }
          _ -> on.Stay(#(dest_path, False))
        }
      }
    }
  )

  run_prettier(".", dest_path, check) |> Some
}

pub fn empty_prettifier(
  _: String,
  _: GhostOfOutputFragment(z),
  _: Option(String),
) -> Option(PrettifierFeedback) {
  Some(PrettifierFeedback(warnings: [], errors: []))
}

// ************************************************************
// Renderer(a, b, c, d, e, f, z)
// ************************************************************

pub type Renderer(
  a, // Assembler error
  b, // Parser error
  c, // Filterer error
  d, // Splitter error
  e, // Emitter error
  f, // Writer error
  z, // VXML Fragment enum
) {
  Renderer(
    assembler: Assembler(a),
    parser: Parser(b),
    filterer: Filterer(c),
    pipeline: Pipeline,
    splitter: Splitter(z, d),
    emitter: Emitter(z, e),
    writer: Writer(z, f),
    prettifier: Prettifier(z),
  )
}

// ************************************************************
// RendererParameters
// ************************************************************

pub type PrettifierMode {
  PrettifierOff
  PrettifierOverwriteOutputDir
  PrettifierToBespokeDir(Option(String))
}

pub type RendererParameters {
  RendererParameters(
    input_dir: String,
    output_dir: String,
    prettifier_behavior: PrettifierMode,
  )
}

pub type RendererOptions(z) {
  RendererOptions(
    verbose: Bool,
    artifacts: Bool,
    steps_table: Bool,
    profiling_table: Option(Int),
    interactive_mode: Bool,
    warnings: Bool,
    only_paths: List(String),
    only_key_vals: List(#(String, String)),
    only_path_key_vals: List(#(String, String, String)),
    dump: Option(List(Int)),
    dump_named: List(#(String, Int, Int)),
    tracker: Option(Tracker),
    echo_assembled_lines: Bool,
    echo_parsed_vxml: Bool,
    echo_filtered_vxml: Bool,
    echo_vxml_fragments: fn(OutputFragment(z, VXML)) -> Bool,
    echo_output_lines_fragments: fn(OutputFragment(z, List(OutputLine))) -> Bool,
    echo_string_fragments: fn(OutputFragment(z, String)) -> Bool,
    echo_prettified_fragments: fn(GhostOfOutputFragment(z)) -> Bool,
  )
}

pub fn vanilla_options() -> RendererOptions(z) {
  RendererOptions(
    verbose: False,
    artifacts: False,
    steps_table: False,
    profiling_table: None,
    interactive_mode: False,
    warnings: False,
    only_paths: [],
    only_key_vals: [],
    only_path_key_vals: [],
    dump: None,
    dump_named: [],
    tracker: None,
    echo_assembled_lines: False,
    echo_parsed_vxml: False,
    echo_filtered_vxml: False,
    echo_vxml_fragments: fn (_) { False },
    echo_output_lines_fragments: fn(_: OutputFragment(z, List(OutputLine))) { False },
    echo_string_fragments: fn(_: OutputFragment(z, String)) { False },
    echo_prettified_fragments: fn(_: GhostOfOutputFragment(z)) { False },
  )
}

// ************************************************************
// CommandLineAmendments
// ************************************************************

pub type Tracker {
  Tracker(
    selector: Option(infra.Selector),
    steps_with_tracking_on_change: List(Int),
    steps_with_tracking_forced: List(Int),
    interactive_mode: Bool,
    desugarer_named_ranges: List(#(String, Int, Int, Bool)),
  )
}

pub type CommandLineAmendments {
  CommandLineAmendments(
    help: Bool,
    input_dir: Option(String),
    output_dir: Option(String),
    only_paths: List(String),
    only_key_vals: List(#(String, String)),
    only_path_key_vals: List(#(String, String, String)),
    prettier: Option(PrettifierMode),
    tracker: Option(Tracker),
    dump: Option(List(Int)),
    dump_named: List(#(String, Int, Int)),
    table: Option(Bool),
    times: Option(Int),
    verbose: Option(Bool),
    artifacts: Option(Bool),
    warnings: Option(Bool),
    timing: Option(Bool),
    echo_assembled: Bool,
    echo_parsed: Bool,
    echo_filtered: Bool,
    vxml_fragments_local_paths_to_echo: Option(List(String)),
    output_lines_fragments_local_paths_to_echo: Option(List(String)),
    string_fragments_local_paths_to_echo: Option(List(String)),
    prettified_fragments_local_paths_to_echo: Option(List(String)),
    user_args: Dict(String, List(String)),
  )
}

// ************************************************************
// empty (default) CommandLineAmendments
// ************************************************************

fn empty_command_line_amendments() -> CommandLineAmendments {
  CommandLineAmendments(
    help: False,
    input_dir: None,
    output_dir: None,
    only_paths: [],
    only_key_vals: [],
    only_path_key_vals: [],
    prettier: None,
    tracker: None,
    dump: None,
    dump_named: [],
    table: None,
    times: None,
    verbose: None,
    artifacts: None,
    warnings: None,
    timing: None,
    echo_assembled: False,
    echo_parsed: False,
    echo_filtered: False,
    vxml_fragments_local_paths_to_echo: None,
    output_lines_fragments_local_paths_to_echo: None,
    string_fragments_local_paths_to_echo: None,
    prettified_fragments_local_paths_to_echo: None,
    user_args: dict.from_list([]),
  )
}

// ************************************************************
// cli_usage
// ************************************************************

pub fn basic_cli_usage(header: String) {
  case header {
    "" -> Nil
    _ -> io.println(header <> "\n")
  }
  let margin = "   "
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
  io.println(margin <> "--dump <step numbers>")
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
  io.println(margin <> "         • add <desugarer-name> before <step numbers> to make the")
  io.println(margin <> "           step numbers relative to occurrences of a given")
  io.println(margin <> "           desugarer in the pipeline; in this case, leaving")
  io.println(margin <> "           <steps number> empty defaults to step numbers '+0-0'")
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
  io.println(margin <> "--verbose")
  io.println(margin <> "  -> verbose renderer output")
  io.println("")
  io.println(margin <> "--artifacts")
  io.println(margin <> "  -> subset of '--verbose' to show which files were printed")
  io.println("")
  io.println(margin <> "--table")
  io.println(margin <> "  -> include a printout of the pipeline steps")
  io.println("")
  io.println(margin <> "--times [<cols=" <> ins(default_times_table_char_width) <> ">]")
  io.println(margin <> "  -> include performance table (how long it takes each desugarer")
  io.println(margin <> "     to run) using <cols> columns")
  io.println("")
}

pub fn advanced_cli_usage(header: String) {
  let margin = "   "
  case header {
    "" -> Nil
    _ -> io.println(header <> "\n")
  }
  io.println(margin <> "--prettier-off")
  io.println(margin <> "  -> disable the prettifier")
  io.println("")
  io.println(margin <> "--prettier-on")
  io.println(margin <> "  -> run prettier --write on each output file in place")
  io.println("")
  io.println(margin <> "--prettier-check")
  io.println(margin <> "  -> run prettier --check on each output file (read-only)")
  io.println("")
  io.println(margin <> "--prettier <dir>")
  io.println(margin <> "  -> run prettier --write, outputting to <dir> instead of output_dir")
  io.println("")
  io.println(margin <> "--warnings/--no-warnings")
  io.println(margin <> "  -> force/suppress long-form printout of warnings")
  io.println("")
  io.println(margin <> "--echo-assembled")
  io.println(margin <> "  -> print the assembled input lines of source")
  io.println("")
  io.println(margin <> "--echo-parsed")
  io.println(margin <> "  -> print the parsed VXML")
  io.println("")
  io.println(margin <> "--echo-filtered")
  io.println(margin <> "  -> print the parsed VXML filtered for key-value pairs")
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
  UnknownOptionArgument(String)
  UnexpectedArgumentsToOption(String)
  DuplicateOption(String)
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
            [one] -> Ok(CommandLineAmendments(..amendments, input_dir: Some(one |> infra.drop_ending_slash)))
            [] -> Error(MissingArgumentToOption("--input-dir"))
            _ -> Error(TooManyArgumentsToOption("--input-dir"))
          }
        }

        "--output-dir" -> {
          case values {
            [one] -> Ok(CommandLineAmendments(..amendments, output_dir: Some(one |> infra.drop_ending_slash)))
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

        "--prettier-off" ->
          case values {
            [] -> Ok(CommandLineAmendments(..amendments, prettier: Some(PrettifierOff)))
            _ -> Error(UnexpectedArgumentsToOption("--prettier-off"))
          }

        "--prettier-on" ->
          case values {
            [] -> Ok(CommandLineAmendments(..amendments, prettier: Some(PrettifierOverwriteOutputDir)))
            _ -> Error(UnexpectedArgumentsToOption("--prettier-on"))
          }

        "--prettier-check" ->
          case values {
            [] -> Ok(CommandLineAmendments(..amendments, prettier: Some(PrettifierToBespokeDir(None))))
            _ -> Error(UnexpectedArgumentsToOption("--prettier-check"))
          }

        "--prettier" ->
          case values {
            [dir] -> Ok(CommandLineAmendments(..amendments, prettier: Some(PrettifierToBespokeDir(Some(dir)))))
            _ -> Error(UnexpectedArgumentsToOption("--prettier"))
          }

        "--track" -> {
          use tracker <- on.ok(parse_track_args(values))
          Ok(
            CommandLineAmendments(
              ..amendments,
              tracker: Some(join_trackers(amendments.tracker, tracker)),
            ),
          )
        }

        "--track-steps" -> {
          use tracker <- on.ok(parse_track_steps_args(values))
          Ok(
            CommandLineAmendments(
              ..amendments,
              tracker: Some(join_trackers(amendments.tracker, tracker)),
            ),
          )
        }

        "--dump" -> {
          use #(numbers, named) <- on.ok(parse_dump_args(values))
          case amendments.dump {
            None -> Ok(CommandLineAmendments(..amendments, dump: Some(numbers), dump_named: list.append(amendments.dump_named, named)))
            _ -> Error(DuplicateOption(option))
          }
        }

        "--echo-assembled" ->
          case list.is_empty(values) {
            True -> Ok(CommandLineAmendments(..amendments, echo_assembled: True))
            False -> Error(UnexpectedArgumentsToOption(option))
          }

        "--echo-parsed" ->
          case list.is_empty(values) {
            True -> Ok(CommandLineAmendments(..amendments, echo_parsed: True))
            False -> Error(UnexpectedArgumentsToOption(option))
          }

        "--echo-filtered" ->
          case list.is_empty(values) {
            True -> Ok(CommandLineAmendments(..amendments, echo_filtered: True))
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
        
        "--artifacts" ->
          case list.is_empty(values) {
            True -> Ok(CommandLineAmendments(..amendments, artifacts: Some(True)))
            False -> Error(UnexpectedArgumentsToOption(option))
          }
        
        "--no-artifacts" ->
          case list.is_empty(values) {
            True -> Ok(CommandLineAmendments(..amendments, artifacts: Some(False)))
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
            False -> Error(UnknownOptionArgument(option))
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
    only_paths: list.append(
      amendments.only_paths,
      args
      |> list.filter(fn(a) { a.0 != "" })
      |> list.map(fn(a) { a.0 })
    ),
    only_key_vals: list.append(
      amendments.only_key_vals,
      args
      |> list.filter(fn(a) {a.0 == "" && { a.1 != "" || a.2 != ""} })
      |> list.map(fn(a) { #(a.1, a.2) })
    ),
    only_path_key_vals: list.append(
      amendments.only_path_key_vals,
      args
      |> list.filter(fn(a) { a.0 != "" && { a.1 != "" || a.2 != ""} })
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
    _ -> {
      list.map(args, fn(arg) {
        let assert [key, value] = string.split(arg, "=")
        // <- this should be generating a CommandLineError instead of asserting
        #(path, key, value)
      })
    }
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

pub fn extract_desugarer_name(input: String) -> #(String, String) {
  let assert Ok(re) = regexp.from_string("^([a-z_][a-z0-9_]*)(.*)")
  case regexp.scan(with: re, content: input) {
    [regexp.Match(_, [Some(prefix), rest, ..])] -> 
      #(prefix, option.unwrap(rest, ""))
    _ -> #("", input)
  }
}

fn parse_step_numbers(
  values: List(String),
) -> Result(#(List(Int), List(Int), List(#(String, Int, Int, Bool))), CommandLineError) {
  use #(on_change, force, named) <- on.ok(
    list.try_fold(values, #([], [], []), fn(acc, val) {
      let original_val = val
      let #(forced, val) = case string.starts_with(val, "!") {
        True -> #(True, string.drop_start(val, 1))
        False -> #(False, val)
      }
      let #(desugarer_name, val) = extract_desugarer_name(val)
      let #(forced, val) = case string.starts_with(val, "!") {
        True -> #(True, string.drop_start(val, 1))
        False -> #(forced, val)
      }
      let #(first_val_negative, val) = case string.starts_with(val, "-") {
        True -> #(True, string.drop_start(val, 1))
        False -> #(False, val)
      }
      let val = infra.drop_prefix(val, "+")
      let multiply_first = fn(x: Int) {
        case first_val_negative {
          True -> -x
          False -> x
        }
      }
      use #(lo, hi) <- on.ok(case splitter.split(splitter.new(["-", "+"]), val) {
        #(before, _, after) if after != "" -> {
          case int.parse(before), int.parse(after) {
            Ok(lo), Ok(hi) -> Ok(#(Some(lo), Some(hi)))
            _, _ -> Error(StepNoValues(
              "unable to parse integer range in '" <> original_val <> "'",
            ))
          }
        }
        _ -> {
          case val {
            "" -> Ok(#(None, None))
            _ -> case int.parse(val) {
              Ok(lo) -> Ok(#(Some(lo), None))
              Error(Nil) -> Error(StepNoValues(
                "unable to parse '" <> original_val <> "' as integer range (1)",
              ))
            }
          }
        }
      })
      case desugarer_name {
        "" -> {
          use lo <- on.none_some(
            lo,
            fn() { Error(StepNoValues("unable to parse '" <> original_val <> "' as integer range (2)")) }
          )
          let hi = option.unwrap(hi, lo)
          let ints = lo_hi_ints(lo |> multiply_first, hi)
          case forced {
            False -> Ok(#(list.append(acc.0, ints), acc.1, acc.2))
            True -> Ok(#(acc.0, list.append(acc.1, ints), acc.2))
          }
        }
        _ -> {
          let lo = option.unwrap(lo, 0) |> multiply_first
          let hi = option.unwrap(hi, lo)
          Ok(#(acc.0, acc.1, [#(desugarer_name, lo, hi, forced), ..acc.2]))
        }
      }
    }),
  )
  let #(on_change, force) = cleanup_step_numbers(on_change, force)
  #(on_change, force, named) |> Ok
}

fn parse_track_args(
  values: List(String),
) -> Result(Tracker, CommandLineError) {
  use first_payload, values <- on.empty_nonempty(
    values,
    fn() { Error(SelectorValues("missing 1st argument")) },
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
    fn() {
      Tracker(
        selector: Some(selector),
        steps_with_tracking_on_change: [],
        steps_with_tracking_forced: [],
        interactive_mode: with_enter,
        desugarer_named_ranges: [],
      )
      |> Ok
    },
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

  use #(on_change, force, named) <- on.ok(parse_step_numbers(values))

  Ok(Tracker(
    selector: Some(selector),
    steps_with_tracking_on_change: on_change,
    steps_with_tracking_forced: force,
    interactive_mode: with_enter,
    desugarer_named_ranges: named,
  ))
}

fn parse_track_steps_args(
  values: List(String),
) -> Result(Tracker, CommandLineError) {
  use #(on_change, force, named) <- on.ok(parse_step_numbers(values))
  let #(with_enter, _) = infra.delete(values, "-i")
  Ok(Tracker(
    selector: None,
    steps_with_tracking_on_change: on_change,
    steps_with_tracking_forced: force,
    interactive_mode: with_enter,
    desugarer_named_ranges: named,
  ))
}

fn join_trackers(
  pm1: Option(Tracker),
  pm2: Tracker,
) -> Tracker {
  use pm1 <- on.eager_none_some(pm1, pm2)
  let #(restrict, force) =
    cleanup_step_numbers(
      list.append(pm1.steps_with_tracking_forced, pm2.steps_with_tracking_forced),
      list.append(
        pm1.steps_with_tracking_on_change,
        pm2.steps_with_tracking_on_change,
      ),
    )
  Tracker(
    selector: case pm1.selector, pm2.selector {
      Some(s1), Some(s2) -> Some(infra.or_selectors(s1, s2))
      _, _ -> option.or(pm1.selector, pm2.selector)
    },
    steps_with_tracking_on_change: restrict,
    steps_with_tracking_forced: force,
    interactive_mode: {
      pm1.interactive_mode ||
      pm2.interactive_mode
    },
    desugarer_named_ranges: list.append(
      pm1.desugarer_named_ranges,
      pm2.desugarer_named_ranges,
    ),
  )
}

fn parse_dump_args(
  values: List(String)
) -> Result(#(List(Int), List(#(String, Int, Int))), CommandLineError) {
  use #(on_change, force, named) <- on.ok(parse_step_numbers(values))
  let numbers = list.append(on_change, force) |> unique_ints
  let named = list.map(named, fn(n) { #(n.0, n.1, n.2) })
  Ok(#(numbers, named))
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
    input_dir: option.unwrap(amendments.input_dir, parameters.input_dir),
    output_dir: option.unwrap(amendments.output_dir, parameters.output_dir),
    prettifier_behavior: option.unwrap(amendments.prettier, parameters.prettifier_behavior),
  )
}

// ************************************************************
// RendererOptions + CommandLineAmendments -> RendererOptions
// ************************************************************

fn exists_match(
  z: Option(List(a)), // List(a) = list of things that might cause a match, left empty if we always want a match
  e: fn(a) -> Bool,   // match tester
) -> Bool {
  case z {
    None -> False
    Some([]) -> True
    Some(x) -> list.any(x, e)
  }
}

pub fn amend_renderer_by_command_line_amendments(
  renderer: Renderer(a, b, c, d, e, f, z),
  _amendments: CommandLineAmendments,
) -> Renderer(a, b, c, d, e, f, z) {
  renderer
}

pub fn amend_renderer_options_by_command_line_amendments(
  options: RendererOptions(z),
  amendments: CommandLineAmendments,
) -> RendererOptions(z) {
  RendererOptions(
    verbose: option.unwrap(amendments.verbose, options.verbose),
    artifacts: option.unwrap(amendments.artifacts, options.artifacts),
    steps_table: option.unwrap(amendments.table, options.steps_table),
    profiling_table: option.or(amendments.times, options.profiling_table),
    interactive_mode: {
      options.interactive_mode ||
      option.map(amendments.tracker, fn(x){x.interactive_mode}) |> option.unwrap(False)
    },
    warnings: option.unwrap(amendments.warnings, options.warnings),
    only_paths: list.append(options.only_paths, amendments.only_paths),
    only_key_vals: list.append(options.only_key_vals, amendments.only_key_vals),
    only_path_key_vals: list.append(options.only_path_key_vals, amendments.only_path_key_vals),
    dump: case options.dump, amendments.dump {
      None, _ -> amendments.dump
      _, None -> options.dump
      Some(x), Some(y) -> Some(list.append(x, y) |> list.sort(int.compare) |> list.unique)
    },
    dump_named: list.append(options.dump_named, amendments.dump_named),
    tracker: case amendments.tracker {
      None -> options.tracker
      Some(x) -> Some(join_trackers(options.tracker, x))
    },
    echo_assembled_lines: amendments.echo_assembled || options.echo_assembled_lines,
    echo_parsed_vxml: amendments.echo_parsed || options.echo_parsed_vxml,
    echo_filtered_vxml: amendments.echo_filtered || options.echo_filtered_vxml || { option.unwrap(amendments.dump, []) |> list.contains(0) },
    echo_vxml_fragments: fn(fr: OutputFragment(z, VXML)) {
      options.echo_vxml_fragments(fr) ||
      exists_match(
        amendments.vxml_fragments_local_paths_to_echo,
        string.contains(fr.path, _),
      )
    },
    echo_output_lines_fragments: fn(fr: OutputFragment(z, List(OutputLine))) {
      options.echo_output_lines_fragments(fr) ||
      exists_match(
        amendments.output_lines_fragments_local_paths_to_echo,
        string.contains(fr.path, _),
      )
    },
    echo_string_fragments: fn(fr: OutputFragment(z, String)) {
      options.echo_string_fragments(fr) ||
      exists_match(
        amendments.string_fragments_local_paths_to_echo,
        string.contains(fr.path, _),
      )
    },
    echo_prettified_fragments: fn(fr: GhostOfOutputFragment(z)) {
      options.echo_prettified_fragments(fr) ||
      exists_match(
        amendments.prettified_fragments_local_paths_to_echo,
        string.contains(fr.path, _),
      )
    },
  )
}

fn apply_dump_named(
  decorateds: List(DecoratedDesugarer),
  dump_named: List(#(String, Int, Int))
) -> Result(List(DecoratedDesugarer), RendererError(a, b, c, d, e, f)) {
  let dump_named = list.map(dump_named, fn(dn) {#(dn.0, dn.1, dn.2, False)})
  use #(on_change, _) <- on.ok(extract_all_on_change_and_forced_steps_from_named_ranges(dump_named, decorateds))
  assert list.length(on_change) >= list.length(dump_named)
  list.index_map(decorateds, fn(decorated, i) {
    let step_no = i + 1
    DecoratedDesugarer(..decorated, dump: list.contains(on_change, step_no))
  })
  |> Ok
}

fn apply_dump_numbers(
  decorateds: List(DecoratedDesugarer),
  dump_numbers: Option(List(Int)),
) -> List(DecoratedDesugarer) {
  use dump_numbers <- on.eager_none_some(dump_numbers, decorateds)
  let num_steps = list.length(decorateds)
  let wraparound = fn(x: Int) {
    case x < 0 {
      True -> num_steps + x + 1
      False -> x
    }
  }
  let apply_to_all = dump_numbers == []
  let dumping_steps = list.map(dump_numbers, wraparound)
  case apply_to_all {
    True -> list.map(
      decorateds,
      fn(decorated) { DecoratedDesugarer(..decorated, dump: True) }
    )
    False -> list.index_map(
      decorateds,
      fn(decorated, i) {
        let step_no = i + 1
        DecoratedDesugarer(..decorated, dump: list.contains(dumping_steps, step_no) )
      }
    )
  }
}

// ************************************************************
// Pipeline + Tracker -> Pipeline (used by above)
// ************************************************************

fn list_int_cleaner(ze_list: List(Int)) -> List(Int) {
  ze_list |> list.unique |> list.sort(int.compare)
}

fn extract_on_change_and_forced_steps_from_name_and_pipeline(
  params: #(String, Int, Int, Bool),
  pipeline: List(DecoratedDesugarer),
) -> Result(#(List(Int), List(Int)), RendererError(a, b, c, d, e, f)) {
  let #(name, lo, hi, forced) = params
  let indices = list.index_fold(
    pipeline,
    [],
    fn(acc, dd, i) {
      case dd.desugarer.name == name {
        True -> [i, ..acc]
        False -> acc
      }
    }
  )
  use _ <- on.stay(
    case indices {
      [] -> on.Return(Error(DesugarerNameNotFoundError(name)))
      _ -> on.Stay(Nil)
    }
  )
  let #(lo, hi) = case lo > hi {
    True -> #(hi, lo)
    False -> #(lo, hi)
  }
  let relative_range = int.range(lo, hi + 1, [], fn(acc, i) { [i, ..acc] })
  let final_range = list.fold(
    indices,
    [],
    fn(acc, index) {
      let step_no = index + 1
      list.fold(
        relative_range,
        acc,
        fn(sub_acc, x) { [step_no + x, ..sub_acc] },
      )
    },
  )
  assert final_range != []
  let final_range = list.unique(final_range)
  case forced {
    True -> #([], final_range)
    False -> #(final_range, [])
  }
  |> Ok
}

fn extract_all_on_change_and_forced_steps_from_named_ranges(
  named_ranges: List(#(String, Int, Int, Bool)),
  pipeline: List(DecoratedDesugarer),
) -> Result(#(List(Int), List(Int)), RendererError(a, b, c, d, e, f)) {
  use #(oa, fo) <- on.ok(list.try_fold(
    named_ranges,
    #([], []),
    fn(acc, named_range) {
      use #(oa, fo) <- on.ok(extract_on_change_and_forced_steps_from_name_and_pipeline(named_range, pipeline))
      #(list.append(acc.0, oa), list.append(acc.1, fo)) |> Ok
    }
  ))
  #(oa |> list_int_cleaner, fo |> list_int_cleaner) |> Ok
}

fn apply_pipeline_tracking_modifier(
  decorateds: List(DecoratedDesugarer),
  tracker: Option(Tracker),
) -> Result(List(DecoratedDesugarer), RendererError(a, b, c, d, e, f)) {
  // if mod is None return the pipeline
  use tracker <- on.eager_none_some(tracker, Ok(decorateds))
  // else...
  let num_steps = list.length(decorateds)
  let wraparound = fn(x: Int) {
    case x < 0 {
      True -> num_steps + x + 1
      False -> x
    }
  }
  let on_change_steps = list.map(tracker.steps_with_tracking_on_change, wraparound)
  let force = list.map(tracker.steps_with_tracking_forced, wraparound)
  use #(named_oa, named_f) <- on.ok(
    extract_all_on_change_and_forced_steps_from_named_ranges(tracker.desugarer_named_ranges, decorateds)
  )
  let on_change_steps = list.append(named_oa, on_change_steps) |> list_int_cleaner
  let force = list.append(named_f, force) |> list_int_cleaner
  let apply_to_all = on_change_steps == [] && force == []
  case apply_to_all {
    True -> {
      list.map(
        decorateds,
        fn(decorated) {
          DecoratedDesugarer(
            desugarer: decorated.desugarer,
            selector: option.unwrap(tracker.selector, decorated.selector),
            tracking_mode: TrackingOnChange,
            dump: decorated.dump,
          )
        }
      )
    }

    False -> {
      list.index_map(decorateds, fn(decorated, i) {
        let step_no = i + 1
        let on_change = list.contains(on_change_steps, step_no)
        let forced = list.contains(force, step_no)
        let mode = case on_change, forced {
          _, True -> TrackingForced
          True, _ -> TrackingOnChange
          _, _ -> TrackingOff
        }
        DecoratedDesugarer(
          desugarer: decorated.desugarer,
          selector: option.unwrap(tracker.selector, decorated.selector),
          tracking_mode: mode,
          dump: decorated.dump,
        )
      })
    }
  }
  |> Ok
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
        List(Duration),
        List(String),
      ),
      InSituDesugaringError,
    ),
  )
}

fn producer(
  main_process_subject: Subject(Message),
  vxml: VXML,
  pipeline: List(DecoratedDesugarer),
) -> Nil {
  let track_any = list.any(pipeline, fn(p) { p.tracking_mode != TrackingOff })
  let last_step = list.length(pipeline)

  let final =
    pipeline
    |> list.try_fold(
      #(vxml, [], [], [], 1, "", False),
      fn(acc, pipe) {
        let #(
          vxml,
          warnings,
          durations,
          lines,
          step_no,
          last_tracking_output,
          got_arrow,
        ) = acc

        let DecoratedDesugarer(desugarer, selector, mode, dump) = pipe

        let #(printed_arrow, lines) = case track_any && !got_arrow {
          True -> {
            #(True, ["    💠", ..lines])
          }
          False -> #(False, lines)
        }

        let now = timestamp.system_time()

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

        let then = timestamp.system_time()
        let duration = timestamp.difference(now, then)
        let durations = [duration, ..durations]

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

        let #(selected_2_print, next_tracking_output) = case mode == TrackingOff && !dump {
          True -> #([], last_tracking_output)

          False -> {
            let selected_2_print =
              vxml
              |> infra.vxml_to_s_lines
              |> selector
            let next_tracking_output =
              selected_2_print
              |> infra.s_lines_table("", True, 0)
            let selected_2_print = case dump {
              True -> vxml |> infra.vxml_to_s_lines |> sl.all()
              False -> selected_2_print
            }
            #(selected_2_print, next_tracking_output)
          }
        }

        let must_print = 
          dump ||
          mode == TrackingForced ||
          { mode == TrackingOnChange && next_tracking_output != last_tracking_output }

        let #(got_arrow, lines) = case must_print {
          True -> {
            let lines = infra.pour(
              pr.name_and_param_string_lines(desugarer, step_no, 4),
              lines,
            )
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
              let lines = ["    ⋮", ..lines]
              #(True, lines)
            }
            False -> #(True, lines)
          }
        }

        #(
          vxml,
          list.append(warnings, new_warnings),
          durations,
          lines,
          step_no + 1,
          next_tracking_output,
          got_arrow,
        )
        |> Ok
      }
    )
    |> result.map(fn(acc) { #(acc.0, acc.1, acc.2, acc.3) })

  send(main_process_subject, ProducerFinished(final))
}

fn loop(
  subject: Subject(Message),
  countdown: Int, // pause for user only when countdown == 0
) -> Result(#(
    VXML,
    List(InSituDesugaringWarning),
    List(Duration),
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
          durations,
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
            durations,
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
  decorateds: List(DecoratedDesugarer),
  interactive_mode: Bool,
) -> Result(#(
    VXML,
    List(InSituDesugaringWarning),
    List(Duration),
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
      decorateds,
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

fn sanitize_input_output_dirs(parameters: RendererParameters) -> RendererParameters {
  RendererParameters(
    ..parameters,
    input_dir: infra.drop_ending_slash(parameters.input_dir),
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

pub type TwoPossibilities(e, f) {
  P1(e)
  P2(f)
}

pub type RendererError(a, b, c, d, e, f) {
  FileOrParseError(a)
  SourceParserError(Blame, b)
  FiltrationError(c)
  DesugarerNameNotFoundError(String)
  PipelineError(InSituDesugaringError)
  UserExitError(Int)
  SplitterError(d)
  EmittingOrWritingErrors(List(TwoPossibilities(e, f)))
}

// ************************************************************
// run_renderer
// ************************************************************

pub fn run_renderer(
  renderer: Renderer(a, b, c, d, e, f, z),
  parameters: RendererParameters,
  options: RendererOptions(z),
) -> Result(List(String), RendererError(a, b, c, d, e, f)) {
  let parameters = sanitize_input_output_dirs(parameters)

  let RendererParameters(
    input_dir,
    output_dir,
    prettifier_mode,
  ) = parameters

  case options.steps_table {
    True -> pr.print_pipeline(renderer.pipeline)
    False -> Nil
  }

  // 🌸 assembling 🌸

  io.println("• assembling...")

  use #(assembled, tree) <- on.error_ok(
    renderer.assembler(input_dir),
    fn(error_a) {
      io.println("  ...assembler error on input_dir " <> input_dir <> ":")
      io.println("")
      [
        #(" ", ins(error_a)),
      ]
      |> pr.two_column_error_announcer(0, 60, "💥", 2, "/ assembler error /")
      |> io.println
      Error(FileOrParseError(error_a))
    },
  )

  case options.verbose, tree {
    True, Some(tree) -> {
      let spaces = 
        string.repeat(" ", string.length("  -> assembled "))

      list.index_map(
        tree |> dt.pretty_print(1),
        fn(line, i) {
          case i == 0 { True -> "  -> assembled " False -> spaces}
          <> line
        }
      )
      |> string.join("\n") |> io.println
    }
    _, _ -> Nil
  }

  case options.echo_assembled_lines {
    False -> Nil
    True -> {
      assembled
      |> io_l.input_lines_table("",  2)
      |> io.println
    }
  }

  // 🌸 parsing 🌸

  io.println("• parsing input lines to VXML...")

  use parsed: VXML <- on.error_ok(
    renderer.parser(assembled),
    on_error: fn(error) {
      let #(blame, c) = error
      io.println("  ...parser error:")
      io.println("")
      [
        #(" blame:", pr.our_blame_digest(blame)),
        #(" error: ", ins(c) |> pr.strip_quotes),
      ]
      |> pr.two_column_error_announcer(0, 70, "💥", 2, "/ parser error /")
      |> io.println
      Error(SourceParserError(blame, c))
    },
  )

  case options.echo_parsed_vxml {
    False -> Nil
    True -> {
      parsed
      |> vp.vxml_to_output_lines
      |> io_l.output_lines_table("parsed:", 2)
      |> io.println
    }
  }

  use filtered <- on.error_ok(
    renderer.filterer(parsed),
    fn (c) {
      io.println("  ...filtration error:")
      io.println("")
      [
        #("", ins(c) |> pr.strip_quotes),
      ]
      |> pr.two_column_error_announcer(0, 70, "💥", 2, "/ filtration error /")
      |> io.println
      Error(FiltrationError(c))
    }
  )

  // use #(filtered, filtration_warnings) <- on.error_ok(
  //   dl.filter_nodes_by_key_values(options.only_key_vals).transform(parsed),
  //   on_error: fn(error) {
  //     let infra.DesugaringError(blame, msg) = error
  //     io.println("  ...key-value filtration error:")
  //     io.println("")
  //     [
  //       #("", ins(msg) |> pr.strip_quotes),
  //     ]
  //     |> pr.two_column_error_announcer(0, 70, "💥", 2, "/ filtration error /")
  //     |> io.println
  //     Error(KeyValueFiltrationError(blame, msg))
  //   },
  // )

  // assert filtration_warnings == []

  // use #(filtered, filtration_warnings) <- on.error_ok(
  //   dl.filter_nodes_by_path_key_values(options.only_path_key_vals).transform(filtered),
  //   on_error: fn(error) {
  //     let infra.DesugaringError(blame, msg) = error
  //     io.println("  ...path-key-value filtration error:")
  //     io.println("")
  //     [
  //       #("", ins(msg) |> pr.strip_quotes),
  //     ]
  //     |> pr.two_column_error_announcer(0, 70, "💥", 2, "/ filtration error /")
  //     |> io.println
  //     Error(KeyValueFiltrationError(blame, msg))
  //   },
  // )

  // assert filtration_warnings == []

  case options.echo_filtered_vxml {
    False -> Nil
    True -> {
      filtered
      |> vp.vxml_to_output_lines
      |> io_l.output_lines_table("filtered:", 2)
      |> io.println
    }
  }

  // 🌸 pipeline 🌸

  io.println("• starting pipeline...")
  let t0 = timestamp.system_time()

  use decorateds <- on.error_ok(
    renderer.pipeline
    |> desugarers_2_decorateds
    |> apply_pipeline_tracking_modifier(options.tracker),
    on_error: fn(error) {
      io.println("  ...error:")
      io.println("")
      [#("", ins(error))]
      |> pr.two_column_error_announcer(0, 70, "💥", 2, "/ '--track' option error: /")
      |> io.println
      Error(error)
    },
  )

  use decorateds <- on.error_ok(
    decorateds
    |> apply_dump_numbers(options.dump)
    |> apply_dump_named(options.dump_named),
    on_error: fn(error) {
      io.println("  ...error:")
      io.println("")
      [#("", ins(error))]
      |> pr.two_column_error_announcer(0, 70, "💥", 2, "/ '--dump' option error /")
      |> io.println
      Error(error)
    },
  )

  use #(desugared, warnings, durations) <- on.error_ok(
    run_pipeline(
      filtered,
      decorateds,
      options.interactive_mode,
    ),
    on_error: fn(e) {
      case e {
        Ok(UserExit(step_no)) -> {
          io.println("")
          io.println("user exit at step_no " <> ins(step_no))
          Error(UserExitError(step_no))
        }
        Error(e) -> {
          io.println("  ...desugaring error:")
          io.println("")
          [
            #(" desugarer:  ", e.desugarer.name <> ".gleam"),
            #(" step: ", ins(e.step_no)),
            #(" blame:", pr.our_blame_digest(e.blame)),
            #(" message:", e.message),
          ]
          |> pr.two_column_error_announcer(0, 68, "🍄", 2, "/ DesugaringError /")
          |> io.println
          Error(PipelineError(e))
        } 
      }
    }
  )

  let t1 = timestamp.system_time()
  let seconds =
    timestamp.difference(t0, t1) |> duration.to_seconds |> float.to_precision(3)

  case options.profiling_table {
    None -> {
      io.println("  ..ended pipeline (" <> ins(seconds) <> "s)")
    }

    Some(total_chars) -> {
      let all_seconds = durations |> list.map(duration.to_seconds) |> list.reverse
      let assert Ok(max_secs) = list.max(all_seconds, float.compare)
      let num_hundreth_seconds = float.ceiling(max_secs *. 100.0)
      let one_hundreth_seconds_num_bars = int.to_float(total_chars) /. num_hundreth_seconds
      let scale =
        list.repeat(Nil, float.round(num_hundreth_seconds) + 1)
        |> list.map_fold(0.0, fn(x, _) { #(x +. 0.01, x) })
        |> pair.second
        |> list.index_fold(
          "",
          fn(acc, seconds, i) {
            let start_char = float.round(int.to_float(i) *. one_hundreth_seconds_num_bars)
            let num_spaces = start_char - string.length(acc)
            case num_spaces > 0 || acc == "" {
              False -> acc
              True -> {
                let label = ins(seconds |> float.to_precision(2)) <> "s"
                acc <> string.repeat(" ", num_spaces) <> label
              }
            }
          }
        )
      assert list.length(all_seconds) == list.length(renderer.pipeline)
      let bars = list.index_map(
        list.zip(renderer.pipeline, all_seconds),
        fn (pair, i) {
          let #(desugarer, seconds) = pair
          let num_bars = float.round(seconds *. 100.0 *. one_hundreth_seconds_num_bars)
          #(ins(i + 1) <> ".", desugarer.name, pr.blocks(num_bars))
        }
      )
      pr.three_column_table([#("#.", "name", scale), ..bars])
      |> pr.print_lines_at_indent(2)
      io.println("  ...ended pipeline in " <> ins(seconds) <> "s")
    }
  }

  // 🌸 splitting 🌸

  io.println("• splitting...")

  use fragments <- on.error_ok(
    renderer.splitter(desugared),
    on_error: fn(error) {
      io.println("  ...splitter error:")
      io.println("")
      [
        #("", ins(error)),
      ]
      |> pr.two_column_error_announcer(0, 68, "🍄", 2, "/ splitter error /")
      |> io.println
      Error(SplitterError(error))
    },
  )

  let prefix = "[" <> output_dir <> "/]"
  let fragments_types_and_paths_4_table =
    list.map(fragments, fn(fr) { #(ins(fr.classifier), prefix <> fr.path) })

  case options.verbose {
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
    case options.echo_vxml_fragments(fr) {
      False -> Nil
      True -> {
        fr.payload
        |> vp.vxml_to_output_lines
        |> io_l.output_lines_table("fr:" <> fr.path, 2)
        |> io.println
      }
    }
  })

  // 🌸 emitting 🌸

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
        case options.echo_output_lines_fragments(fr) {
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
      use error <- on.ok_error(fr, fn(_){ Nil })
      io.println("  emitter error:")
      io.println("")
      [
        #("", ins(error)),
      ]
      |> pr.two_column_error_announcer(0, 68, "🍄", 2, "/ emitter error /")
      |> io.println
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

  // 🌸 writing 🌸

  io.println("• writing String fragments to files...")

  fragments
  |> list.each(fn(result) {
    case result {
      Error(_) -> Nil
      Ok(fr) -> {
        case options.echo_string_fragments(fr) {
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

  let singleton_fragment = case fragments {
    [_] -> True
    _ -> False
  }

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
            case singleton_fragment {
              True -> io.println("  -> wrote [" <> output_dir <> "/]" <> fr.path)
              False -> case options.verbose || options.artifacts {
                True -> io.println("  wrote [" <> output_dir <> "/]" <> fr.path)
                False -> Nil
              }
            }
            #(acc + 1, Ok(z))
          }
        }
      }
    )

  case options.verbose || options.artifacts {
    False -> case count {
      1 -> case singleton_fragment { 
        True -> Nil // we already announced (see above)
        False -> io.println("  -> wrote 1 file (use '--artifacts' or '--verbose' to see)")
      }
      _ -> io.println("  -> wrote " <> ins(count) <> " files (use '--artifacts' or '--verbose' to see)")
    }
    True -> Nil
  }

  // 🌸 prettifying 🌸

  let run_prettification = fn(result, dest_dir) {
    use fr: GhostOfOutputFragment(z) <- on.eager_error_ok(result, Nil)
    case dest_dir {
      None ->
        io.print("  prettify-checking [" <> output_dir <> "]" <> fr.path <> "...")
      Some(dir) ->
        io.print(
          "  prettifying [" <> output_dir <> "/]" <> fr.path
          <> " -> [" <> dir <> "/]" <> fr.path <> "...",
        )
    }
    case renderer.prettifier(output_dir, fr, dest_dir) {
      None -> {
        io.println("skipped")
      }
      Some(PrettifierFeedback(warnings: warns, errors: errs)) -> {
        let x = list.length(warns)
        let y = list.length(errs)
        let warn_suffix = case x > 0 && !options.warnings {
          True -> " (use '--warnings' to see)"
          False -> ","
        }
        let end = case y > 0 || { x > 0 && options.warnings } {
          True -> ":\n"
          False -> "\n"
        }
        io.print(
          " " <> ins(x) <> " warnings" <> warn_suffix
          <> " " <> ins(y) <> " errors" <> end,
        )
        case options.warnings {
          True ->
            list.each(warns, fn(w) {
              io.println("  👾👾--- warning ---👾👾: " <> w)
            })
          False -> Nil
        }
        list.each(errs, fn(e) {
          io.println("  🍄🍄--- error ---🍄🍄: " <> e)
        })
      }
    }
  }

  case prettifier_mode {
    PrettifierOff -> Nil
    _ -> {
      io.println("• prettifying:")
      let dest_dir = case prettifier_mode {
        PrettifierOverwriteOutputDir -> Some(output_dir)
        PrettifierToBespokeDir(dir) -> dir
        _ -> panic
      }
      list.each(fragments, run_prettification(_, dest_dir))
    }
  }

  fragments
  |> list.each(fn(result) {
    use fr <- on.error_ok(result, fn(_) { Nil })
    case options.echo_prettified_fragments(fr) {
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

  // 👾 warnings 👾

  case list.length(warnings) {
    0 -> Nil
    _ -> {
      case options.warnings {
        True ->
          io.println("\n👉 " <> pr.how_many("warning", "warnings", list.length(warnings)) <> ":")
        False ->
          io.println("\n[" <> pr.how_many("suppressed warning", "suppressed warnings", list.length(warnings)) <> " (use '--warnings' option to see)]")
      }
    }
  }

  case options.warnings {
    True ->
      list.each(
        warnings,
        fn (w) {
          io.println("")
          [
            #(" from:", w.desugarer.name <> " (desugarer)"),
            #(" pipeline step: ", ins(w.step_no)),
            #(" blame:", bl.blame_digest(w.blame)),
            #(" message:", w.message),
          ]
          |> pr.two_column_error_announcer(0, 60, "👾", 2, "")
          |> io.println
        }
      )
    False -> Nil
  }

  let #(oks, errors) = result.partition(fragments)

  case errors {
    [] -> Ok(oks |> list.map(fn(ghost) { ghost.path }))
    _ -> Error(EmittingOrWritingErrors(errors))
  }
}
