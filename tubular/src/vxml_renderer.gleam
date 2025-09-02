import blame.{Em, type Blame} as bl
import io_lines.{type InputLine, type OutputLine, OutputLine} as io_l
import desugarer_library as dl
import gleam/dict.{type Dict}
import gleam/float
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string.{inspect as ins}
import gleam/time/duration
import gleam/time/timestamp.{type Timestamp}
import infrastructure.{type Desugarer, Pipe, type Pipeline, TrackingOff, TrackingForced, TrackingOnChange} as infra
import selector_library as sl
import shellout
import simplifile
import table_and_co_printer as pr
import vxml.{type VXML, V} as vp
import writerly as wp
import on

// ************************************************************
// Assembler(a)                                                // 'a' is assembler error type; "assembler" = "source assembler"
// file/directory -> List(InputLine)
// ************************************************************

pub type Assembler(a) =
  fn(String) -> Result(List(InputLine), a)

pub type AssemblerDebugOptions {
  AssemblerDebugOptions(echo_: Bool)
}

// ************************************************************
// default assembler
// ************************************************************

pub fn default_assembler(
  spotlight_paths: List(String),
) -> Assembler(wp.AssemblyError) {
  let spaces = string.repeat(" ", string.length("• assembling "))
  fn(input_dir) {
    use #(directory_tree, assembled) <- on.ok(
      wp.assemble_input_lines_advanced_mode(input_dir, spotlight_paths),
    )
    let directory_tree =
      list.map(directory_tree, fn(line) { spaces <> line }) |> list.drop(1)
    io.println(input_dir)
    case directory_tree {
      [] -> Nil
      _ -> io.println(string.join(directory_tree, "\n"))
    }
    Ok(assembled)
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

// ************************************************************
// default writerly parser
// ************************************************************

pub fn default_writerly_parser(
  only_args: List(#(String, String, String)),
) -> Parser(String) {
  fn(lines) {
    use writerlys <- on.error_ok(
      wp.parse_input_lines(lines),
      fn(e) { Error(#(e.blame, ins(e))) },
    )

    use vxml <- on.error_ok(
      writerlys |> wp.writerlys_to_vxmls |> infra.get_root,
      fn(e) { Error(#(bl.no_blame, ins(e))) },
    )

    use #(filtered_vxml, _) <- on.error_ok(
      dl.filter_nodes_by_attributes(only_args).transform(vxml),
      fn(_) { Error(#(bl.no_blame, "empty document after filtering nodes by: " <> ins(only_args))) },
    )

    Ok(filtered_vxml)
  }
}

// ************************************************************
// default html parser
// ************************************************************

pub fn default_html_parser(
  only_args: List(#(String, String, String)),
) -> Parser(String) {
  fn(lines: List(InputLine)) {
    // we don't have our own html parser that can give
    // proper blames, we have to resort to this nonsense
    let assert [first_line, ..] = lines
    let path = case first_line.blame {
      bl.Src(_, path, _, _) -> path
      _ -> "vr::default_html_parser"
    }

    let content =
      lines
      |> io_l.input_lines_to_output_lines
      |> io_l.output_lines_to_string
      |> string.trim

    use <- on.true_false(
      content == "",
      Error(#(first_line.blame, "empty content")),
    )

    use vxml <- on.error_ok(
      content |> vp.xmlm_based_html_parser(path),
      fn(xmlm_parse_error) { Error(#(bl.no_blame, "xmlm parse error: " <> ins(xmlm_parse_error))) },
    )

    use #(vxml, _) <- on.error_ok(
      dl.filter_nodes_by_attributes(only_args).transform(vxml),
      fn(_) { Error(#(bl.no_blame, "empty document after filtering nodes by: " <> ins(only_args))) },
    )

    Ok(vxml)
  }
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

// ************************************************************
// stub splitter
// ************************************************************

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
// OutputFragment(d) -> #(String, List(OutputLine), d)         // #(local_path, output_lines, fragment_type)
// ************************************************************

pub type Emitter(d, f) =
  fn(OutputFragment(d, VXML)) -> Result(OutputFragment(d, List(OutputLine)), f)

pub type EmitterDebugOptions(d) {
  EmitterDebugOptions(
    echo_: fn(OutputFragment(d, List(OutputLine))) -> Bool,
  )
}

// ************************************************************
// stub writerly emitter
// ************************************************************

pub fn stub_writerly_emitter(
  fragment: OutputFragment(d, VXML),
) -> Result(OutputFragment(d, List(OutputLine)), b) {
  let lines =
    fragment.payload
    |> wp.vxml_to_writerlys
    |> list.map(wp.writerly_to_output_lines)
    |> list.flatten

  Ok(OutputFragment(..fragment, payload: lines))
}

// ************************************************************
// stub html emitter
// ************************************************************

pub fn stub_html_emitter(
  fragment: OutputFragment(d, VXML),
) -> Result(OutputFragment(d, List(OutputLine)), b) {
  let lines =
    list.flatten([
      [
        OutputLine(Em([], "stub_html_emitter"), 0, "<!DOCTYPE html>"),
        OutputLine(Em([], "stub_html_emitter"), 0, "<html>"),
        OutputLine(Em([], "stub_html_emitter"), 0, "<head>"),
        OutputLine(Em([], "stub_html_emitter"), 2, "<link rel=\"icon\" type=\"image/x-icon\" href=\"logo.png\">"),
        OutputLine(Em([], "stub_html_emitter"), 2, "<meta charset=\"utf-8\">"),
        OutputLine(Em([], "stub_html_emitter"), 2, "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">"),
        OutputLine(Em([], "stub_html_emitter"), 2, "<script type=\"text/javascript\" src=\"./mathjax_setup.js\"></script>"),
        OutputLine(Em([], "stub_html_emitter"), 2, "<script type=\"text/javascript\" id=\"MathJax-script\" async src=\"https://cdn.jsdelivr.net/npm/mathjax@3/es5/tex-svg.js\"></script>"),
        OutputLine(Em([], "stub_html_emitter"), 0, "</head>"),
        OutputLine(Em([], "stub_html_emitter"), 0, "<body>"),
      ],
      fragment.payload
        |> infra.v_get_children
        |> list.map(fn(vxml) { vp.vxml_to_html_output_lines(vxml, 2, 2) })
        |> list.flatten,
      [
        OutputLine(Em([], "stub_html_emitter"), 0, "</body>"),
        OutputLine(Em([], "stub_html_emitter"), 0, ""),
      ],
    ])
  Ok(OutputFragment(..fragment, payload: lines))
}

// ************************************************************
// stub jsx emitter
// ************************************************************

pub fn stub_jsx_emitter(
  fragment: OutputFragment(d, VXML),
) -> Result(OutputFragment(d, List(OutputLine)), b) {
  let lines =
    list.flatten([
      [
        OutputLine(Em([], "panel_emitter"), 0, "import Something from \"./Somewhere\";",),
        OutputLine(Em([], "panel_emitter"), 0, ""),
        OutputLine(Em([], "panel_emitter"), 0, "const OurSuperComponent = () => {"),
        OutputLine(Em([], "panel_emitter"), 2, "return ("),
        OutputLine(Em([], "panel_emitter"), 4, "<>"),
      ],
      vp.vxmls_to_jsx_output_lines(fragment.payload |> infra.v_get_children, 6),
      [
        OutputLine(Em([], "panel_emitter"), 4, "</>"),
        OutputLine(Em([], "panel_emitter"), 2, ");"),
        OutputLine(Em([], "panel_emitter"), 0, "};"),
        OutputLine(Em([], "panel_emitter"), 0, ""),
        OutputLine(Em([], "panel_emitter"), 0, "export default OurSuperComponent;"),
      ],
    ])
  Ok(OutputFragment(..fragment, payload: lines))
}

// ************************************************************
// Writer (the thing that prints to files; no type or function supplied; only a debug option)
// ************************************************************

pub type WriterDebugOptions(d) {
  WriterDebugOptions(echo_: fn(OutputFragment(d, String)) -> Bool)
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

// ************************************************************
// default & empty prettifier
// ************************************************************

pub fn run_prettier(in: String, path: String, check: Bool) -> Result(String, #(Int, String)) {
  shellout.command(
    run: "npx",
    in: in,
    with: [
      "prettier",
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
      use _ <- result.try(
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
  h, // Prettifier error type
) {
  Renderer(
    assembler: Assembler(a),             // file/directory -> List(InputLine)                                    Result w/ error type a
    parser: Parser(c),                   // List(InputLine) -> VXML                                              Result w/ error type c
    pipeline: Pipeline,                  // VXML -> ... -> VXML                                                  Result w/ error type InSituDesugaringError
    splitter: Splitter(d, e),            // VXML -> List(OutputFragment(d, VXML))                                Result w/ error type e
    emitter: Emitter(d, f),              // OutputFragment(d, VXML) -> OutputFragment(d, String)                 Result w/ error type f
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
  )
}

// ************************************************************
// RendererDebugOptions(d)                                     // 'd' is fragment classifier type
// ************************************************************

pub type RendererDebugOptions(d) {
  RendererDebugOptions(
    assembler_debug_options: AssemblerDebugOptions,
    parser_debug_options: ParserDebugOptions,
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
    table: Option(Bool),
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
    table: None,
    input_dir: None,
    output_dir: None,
    echo_assembled: False,
    track: None,
    vxml_fragments_local_paths_to_echo: None,
    output_lines_fragments_local_paths_to_echo: None,
    printed_string_fragments_local_paths_to_echo: None,
    prettified_string_fragments_local_paths_to_echo: None,
    only_key_values: [],
    only_paths: [],
    prettier: None,
    user_args: dict.from_list([]),
  )
}

// ************************************************************
// cli_usage
// ************************************************************

pub fn basic_cli_usage() {
  let margin = "   "
  io.println("")
  io.println("Renderer options:")
  io.println("")
  io.println(margin <> "--help")
  io.println(margin <> "  -> print this message")
  io.println("")
  io.println(margin <> "--only <string1> <string2> ...")
  io.println(margin <> "  -> restrict source to files whose paths contain at least one of")
  io.println(margin <> "     the given strings (as a substring)")
  io.println("")
  io.println(margin <> "--only <key1=val1> <key2=val2> ...")
  io.println(margin <> "  -> restrict source to elements that have at least one of the")
  io.println(margin <> "     given key-value pairs as attributes (& ancestors of such)")
  io.println("")
  io.println(margin <> "--table")
  io.println(margin <> "  -> include a printout of the pipeline table in the rendering")
  io.println(margin <> "     output")
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
  io.println(margin <> "--prettier [<dir>]")
  io.println(margin <> "  -> turn the prettifier on and have the prettifier output to")
  io.println(margin <> "     <dir>; if absent, <dir> defaults to")
  io.println(margin <> "     renderer_parameters.output_dir")
  io.println("")
}

pub fn extended_cli_usage() {
  let margin = "   "
  io.println("")
  io.println("Esoteric renderer options:")
  io.println("")
  io.println(margin <> "--track-steps")
  io.println(margin <> "  -> takes arguments in the same form as <step numbers> option of")
  io.println(margin <> "     --track, with the same semantics (to edit the tracking steps", )
  io.println(margin <> "     of a tracker set up code-side)", )
  io.println("")
  io.println(margin <> "--echo-assembled")
  io.println(margin <> "  -> print the assembled input lines of source")
  io.println("")
  io.println(margin <> "--echo-fragments <subpath1> <subpath2> ...")
  io.println(margin <> "  -> echo fragments whose paths contain one of the given subpaths")
  io.println(margin <> "     before conversion to output lines, list none to match all", )
  io.println("")
  io.println(margin <> "--echo-fragments-ol <subpath1> <subpath2> ...")
  io.println(margin <> "  -> echo fragments whose paths contain one of the given subpaths")
  io.println(margin <> "     after conversion to output lines, list none to match all", )
  io.println("")
  io.println(margin <> "--echo-fragments-printed <subpath1> <subpath2> ...")
  io.println(margin <> "  -> echo fragments whose paths contain one of the given subpaths")
  io.println(margin <> "     in string form before prettifying, list none to match all", )
  io.println("")
  io.println(margin <> "--echo-fragments-prettified <local_path1> <local_path2> ...", )
  io.println(margin <> "  -> echo fragments whose paths contain one of the given subpaths")
  io.println(margin <> "     in string form after prettifying, list none to match all", )
  io.println("")
}

// ************************************************************
// process_command_line_arguments
// ************************************************************

pub type CommandLineError {
  ExpectedDoubleDashString(String)
  UnwantedOptionArgument(String)
  UnexpectedArgumentsToOption(String)
  SelectorValues(String)
  StepNoValues(String)
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
      use amendments <- result.try(result)
      let #(option, values) = pair
      case option {
        "--help" -> {
          basic_cli_usage()
          io.println("")
          case list.is_empty(values) {
            True -> Ok(CommandLineAmendments(..amendments, help: True))
            False -> Error(UnexpectedArgumentsToOption("option"))
          }
        }

        "--only" -> {
          let args =
            values
            |> list.map(parse_attribute_value_args_in_filename)
            |> list.flatten()
          Ok(amendments |> amend_only_args(args))
        }

        "--table" ->
          case list.is_empty(values) {
            True -> Ok(CommandLineAmendments(..amendments, table: Some(True)))
            False -> Error(UnexpectedArgumentsToOption("--table"))
          }

        "--prettier" ->
          case values {
            [dir] -> Ok(CommandLineAmendments(..amendments, prettier: Some(PrettifierToBespokeDir(dir))))
            [] -> Ok(CommandLineAmendments(..amendments, prettier: Some(PrettifierOverwriteOutputDir)))
            _ -> Error(UnexpectedArgumentsToOption("--prettier2"))
          }

        "--track" -> {
          use pipeline_mod <- result.try(parse_track_args(values))
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
          use pipeline_mod <- result.try(parse_show_change_at_steps_args(values))
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

        "--echo-assembled" ->
          case list.is_empty(values) {
            True -> Ok(CommandLineAmendments(..amendments, echo_assembled: True))
            False -> Error(UnexpectedArgumentsToOption(option))
          }

        "--echo-fragments" ->
          Ok(
            CommandLineAmendments(
              ..amendments,
              vxml_fragments_local_paths_to_echo: Some(values),
            ),
          )

        "--echo-fragments-ol" ->
          Ok(
            CommandLineAmendments(
              ..amendments,
              output_lines_fragments_local_paths_to_echo: Some(values),
            ),
          )

        "--echo-fragments-printed" ->
          Ok(
            CommandLineAmendments(
              ..amendments,
              printed_string_fragments_local_paths_to_echo: Some(values),
            ),
          )

        "--echo-fragments-prettified" ->
          Ok(
            CommandLineAmendments(
              ..amendments,
              prettified_string_fragments_local_paths_to_echo: Some(values),
            ),
          )

        _ -> {
          case list.contains(user_keys, option) {
            True -> Ok(CommandLineAmendments(..amendments, user_args: dict.insert(amendments.user_args, option, values)))
            False -> Error(UnwantedOptionArgument(option))
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
    only_key_values: list.append(amendments.only_key_values, args),
    only_paths: list.append(
      amendments.only_paths,
      args
        |> list.map(fn(a) {
          let #(path, _, _) = a
          path
        }),
    ),
  )
}

fn parse_attribute_value_args_in_filename(
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
  use #(restrict, force) <- result.try(
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
      use ints <- result.try(case string.split_once(val, "-") {
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

  use second_payload, values <- on.empty_nonempty(
    values,
    Ok(
      PipelineTrackingModifier(
        selector: Some(selector),
        steps_with_tracking_on_change: [],
        steps_with_tracking_forced: [],
      ),
    ),
  )

  use plus_minus <- on.error_ok(
    parse_plus_minus(second_payload),
    fn(_) {
      Error(SelectorValues(
        "2nd argument to --show-changes-near should have form +<p>-<m> or -<m>+<p> where p, m are integers",
      ))
    },
  )

  let selector =
    selector
    |> infra.extend_selector_up(plus_minus.minus)
    |> infra.extend_selector_down(plus_minus.plus)

  use #(restrict, force) <- result.try(
    parse_step_numbers(values)
  )

  Ok(PipelineTrackingModifier(
    selector: Some(selector),
    steps_with_tracking_on_change: restrict,
    steps_with_tracking_forced: force,
  ))
}

fn parse_show_change_at_steps_args(
  values: List(String),
) -> Result(PipelineTrackingModifier, CommandLineError) {
  use #(restrict, force) <- result.try(
    parse_step_numbers(values)
  )

  Ok(PipelineTrackingModifier(
    selector: None,
    steps_with_tracking_on_change: restrict,
    steps_with_tracking_forced: force,
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
  )
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
  renderer: Renderer(a, c, d, e, f, h),
  amendments: CommandLineAmendments,
) -> Renderer(a, c, d, e, f, h) {
  case amendments.track {
    None -> renderer
    Some(cli) ->
      Renderer(
        ..renderer,
        pipeline: apply_pipeline_tracking_modifier(
          renderer.pipeline,
          cli,
        ),
      )
  }
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

// ************************************************************
// Pipeline + PipelineTrackingModifier -> Pipeline (used by above)
// ************************************************************

pub fn apply_pipeline_tracking_modifier(
  pipeline: Pipeline,
  mod: PipelineTrackingModifier,
) -> Pipeline {
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
        )
      })
    }
  }
}

// ************************************************************
// run_pipeline
// ************************************************************

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

fn run_pipeline(
  vxml: VXML,
  pipeline: Pipeline,
) -> Result(#(VXML, List(InSituDesugaringWarning), List(#(Int, Timestamp))), InSituDesugaringError) {
  let track_any = list.any(pipeline, fn(p) { p.tracking_mode != TrackingOff })
  let last_step = list.length(pipeline)

  pipeline
  |> list.try_fold(
    #(vxml, 1, "", [], [], False),
    fn(acc, pipe) {
      let #(vxml, step_no, last_tracking_output, times, warnings, got_arrow) = acc
      let Pipe(desugarer, selector, mode) = pipe
      let times = case desugarer.name == "timer" {
        True -> [#(step_no, timestamp.system_time()), ..times]
        False -> times
      }
      let printed_arrow = case track_any && !got_arrow {
        True -> {
          io.println("    💠")
          True
        }
        False -> False
      }
      use #(vxml, new_warnings) <- on.error_ok(desugarer.transform(vxml), fn(error) {
        Error(InSituDesugaringError(
          desugarer: desugarer,
          step_no: step_no,
          blame: error.blame,
          message: error.message,
        ))
      })
      let new_warnings = list.map(new_warnings, fn(warning) {
        InSituDesugaringWarning(
          desugarer: desugarer,
          step_no: step_no,
          blame: warning.blame,
          message: warning.message,
        )
      })
      let #(selected, next_tracking_output) = case mode == TrackingOff {
        True -> #([], last_tracking_output)
        False -> {
          let selected = vxml |> infra.vxml_to_s_lines |> selector
          #(selected, selected |> infra.s_lines_annotated_table("", True, 0))
        }
      }
      let must_print = mode == TrackingForced || { mode == TrackingOnChange && next_tracking_output != last_tracking_output }
      let got_arrow = case must_print {
        True -> {
          io.println("    " <> pr.name_and_param_string(desugarer, step_no))
          io.println("    💠")
          selected
          |> infra.s_lines_annotated_table("", False, 2)
          |> io.println
          False
        }
        False -> case printed_arrow && step_no < last_step {
          True -> {
            io.println("    ⋮")
            True
          }
          False -> True
        }
      }
      #(vxml, step_no + 1, next_tracking_output, times, list.append(warnings, new_warnings), got_arrow)
      |> Ok
    }
  )
  |> result.map(fn(acc) { #(acc.0, acc.4, acc.3) })
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
    use exists <- result.try(simplifile.is_directory(acc))
    use _ <- result.try(
      case exists {
        True  -> Ok(Nil)
        False -> simplifile.create_directory(acc)
      }
    )
    Ok(acc)
  })
  |> result.map(fn(_) { Nil })
}

fn output_dir_local_path_printer(
  output_dir: String,
  local_path: String,
  content: String,
) -> Result(Nil, simplifile.FileError) {
  let assert False = string.starts_with(local_path, "/")
  let assert False = string.ends_with(output_dir, "/")
  let path = output_dir <> "/" <> local_path
  use _ <- result.try(create_dirs_on_path_to_file(path))
  simplifile.write(path, content)
}

// ************************************************************
// run_renderer return type(s)
// ************************************************************

pub type ThreePossibilities(f, g, h) {
  P1(f)
  P2(g)
  P3(h)
}

pub type RendererError(a, c, e, f, h) {
  FileOrParseError(a)
  SourceParserError(Blame, c)
  PipelineError(InSituDesugaringError)
  SplitterError(e)
  EmittingOrPrintingOrPrettifyingErrors(List(ThreePossibilities(f, String, h)))
}

// ************************************************************
// run_renderer
// ************************************************************

pub fn run_renderer(
  renderer: Renderer(a, c, d, e, f, h),
  parameters: RendererParameters,
  debug_options: RendererDebugOptions(d),
) -> Result(Nil, RendererError(a, c, e, f, h)) {
  io.println("")

  let parameters = sanitize_output_dir(parameters)
  let RendererParameters(
    table,
    input_dir,
    output_dir,
    prettifier_mode,
  ) = parameters

  case table {
    True -> pr.print_pipeline(renderer.pipeline |> infra.pipeline_desugarers)
    False -> Nil
  }

  // 🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸
  // 🌸 assembling~ 🌸
  // 🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸

  io.print("• assembling ")

  use assembled <- on.error_ok(
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

  case debug_options.assembler_debug_options.echo_ {
    False -> Nil
    True -> {
      io_l.input_lines_annotated_table_at_indent(assembled, "",  2)
      |> string.join("\n")
      |> io.println
      Nil
    }
  }

  // 🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸
  // 🌸 parsing~~~~ 🌸
  // 🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸

  io.println("• parsing input lines to VXML")

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

  use #(desugared, warnings, times) <- on.error_ok(
    run_pipeline(parsed, renderer.pipeline),
    on_error: fn(e: InSituDesugaringError) {
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
    },
  )

  let t1 = timestamp.system_time()
  let seconds =
    timestamp.difference(t0, t1) |> duration.to_seconds |> float.to_precision(2)

  io.println("  ...ended pipeline (" <> ins(seconds) <> "s);")

  case list.length(times) > 0 {
    False -> Nil
    True -> {
      let times = [#(list.length(renderer.pipeline), t1), ..times]
      list.fold(times |> list.reverse, #(0, t0), fn(acc, next) {
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

  io.println("• splitting the vxml...")

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

  io.println("  -> obtained " <> pr.how_many("fragment", "fragments", list.length(fragments)) <> ":")
  
  [#("classifier", "path"), ..fragments_types_and_paths_4_table]
  |> pr.two_column_table
  |> pr.print_lines_at_indent(2)

  fragments
  |> list.each(fn(fr) {
    case debug_options.splitter_debug_options.echo_(fr) {
      False -> Nil
      True -> {
        fr.payload
        |> vp.vxml_to_output_lines
        |> io_l.echo_output_lines("fr:" <> fr.path)
        Nil
      }
    }
  })

  // 🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸
  // 🌸 emitting~~~ 🌸
  // 🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸

  io.print("• converting fragments to output line fragments")

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
            |> io_l.echo_output_lines("fr-ol:" <> fr.path)
            Nil
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

  // 🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸
  // 🌸 writing (to file)~~ 🌸
  // 🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸

  io.println("• converting output line fragments to string fragments")

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

  io.println("• writing string fragments to files")

  let fragments =
    fragments
    |> list.map(fn(result) {
      use fr <- result.try(result)
      let brackets = "[" <> output_dir <> "/]"
      case output_dir_local_path_printer(output_dir, fr.path, fr.payload) {
        Ok(Nil) -> {
          io.println("  wrote " <> brackets <> fr.path)
          Ok(GhostOfOutputFragment(fr.classifier, fr.path))
        }
        Error(file_error) ->
          Error(P2(
            { file_error |> ins } <> " on path " <> output_dir <> "/" <> fr.path,
          ))
      }
    })

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
      use fr <- result.try(result)
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

  // 🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸
  // 🌸 reporting pipeline warnings 🌸
  // 🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸

  case list.length(warnings) {
    0 -> Nil
    _ -> {
      io.println("\n👉 " <> pr.how_many("warning", "warnings", list.length(warnings)) <> ":")
    }
  }

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

  let #(_, errors) = result.partition(fragments)

  case list.length(errors) > 0 {
    True -> {
      Error(EmittingOrPrintingOrPrettifyingErrors(errors))
    }
    False -> Ok(Nil)
  }
}
