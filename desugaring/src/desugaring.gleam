import desugaring/core.{type Desugarer, type Pipeline}
import desugaring/desugarers as dl
import desugaring/generate_local_desugarers_dot_gleam as local_desugarer_generator
import desugaring/renumber_local_desugarer_blames as local_desugarer_blame_renumberer
import desugaring/selectors as sl
import desugaring/tables as pr
import desugaring/testing
import desugaring/tracking.{type Selector}
import dirtree.{type DirTree} as dt
import either_or.{Either, Or}
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject, receive, send, spawn}
import gleam/float
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/pair
import gleam/regexp
import gleam/result
import gleam/string.{inspect as ins}
import gleam/time/duration.{type Duration}
import gleam/time/timestamp
import input
import on
import shellout
import simplifile
import vxml.{type VXML, V} as vp
import vxml/blame.{type Blame, Ext} as bl
import vxml/io_lines.{type InputLine, type OutputLine, OutputLine} as io_l

const default_times_table_char_width = 90

pub const help_message_margin = 3

const pipeline_runner_margin = 2

const tracking_progress_interval = 10

const tracking_progress_quiet_steps = 3

// MacBook 16' can take 140

pub type MonitorOutputMargin {
  AtRunnerMargin
  Verbatim
}

pub type MonitorOutput {
  MonitorOutput(lines: List(String), margin: MonitorOutputMargin)
}

pub type PipelineStepContext {
  PipelineStepContext(
    step_no: Int,
    previous_desugarer: Option(Desugarer),
    next_desugarer: Option(Desugarer),
  )
}

type MonitorUpdate {
  MonitorUpdate(next: Monitor, outputs: List(MonitorOutput))
}

pub opaque type Monitor {
  Monitor(
    name: String,
    update: fn(VXML, PipelineStepContext) -> Result(MonitorUpdate, String),
  )
}

pub opaque type MonitorFactory {
  TrackingMonitorFactory(Tracker)
  DumpMonitorFactory(List(PipelineStepSpec), VxmlMonitorOutput)
}

pub fn new_monitor(
  name: String,
  state: state,
  update: fn(VXML, state, PipelineStepContext) ->
    Result(#(state, List(MonitorOutput)), String),
) -> Monitor {
  Monitor(name: name, update: fn(vxml, context) {
    use #(next_state, outputs) <- on.ok(update(vxml, state, context))
    Ok(MonitorUpdate(
      next: new_monitor(name, next_state, update),
      outputs: outputs,
    ))
  })
}

// ************************************************************
// Assembler(a)                                                // 'a' is assembler error type; "assembler" = "source assembler"
// file/directory -> List(InputLine)
// ************************************************************

pub type Assembler(a) =
  fn(String) -> Result(#(List(InputLine), Option(DirTree)), a)

// the 'List(String)' is a feedback/success message on assembly

pub fn default_file_assembler(
  path: String,
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

pub fn default_xml_parser(
  lines: List(InputLine),
) -> Result(VXML, #(Blame, String)) {
  vp.parse_xml_input_lines(lines)
  |> result.map_error(fn(e) { #(bl.no_blame, "xml parse error: " <> ins(e)) })
}

pub const default_html_parser = default_xml_parser

// ************************************************************
// Filterer(c)                                                 // 'c' is filterer error type
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
    dl.filter_nodes_by_path_key_values_while_saving(#(
      options.only_path_key_vals,
      saving,
    )).transform(vxml),
    fn(e) { Error(e.message) },
  )
  assert warnings == []
  use #(vxml, warnings) <- on.error_ok(
    dl.filter_nodes_by_key_values_while_saving(#(options.only_key_vals, saving)).transform(
      vxml,
    ),
    fn(e) { Error(e.message) },
  )
  assert warnings == []
  Ok(vxml)
}

// ************************************************************
// Splitter(z, d)                                              // 'z' is fragment classifier type, 'd' is splitter error type
// VXML -> List(OutputFragment)
// ************************************************************

pub type OutputFragment(z, p) {
  // 'z' is fragment classifier type, 'p' is payload type (VXML or List(OutputLine))
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

pub fn stub_html_emitter(
  fragment: OutputFragment(z, VXML),
) -> Result(OutputFragment(z, List(OutputLine)), b) {
  let blame = Ext([], "stub_html_emitter")
  let lines =
    list.flatten([
      [
        OutputLine(blame, 0, "<!DOCTYPE html>"),
        OutputLine(blame, 0, "<html>"),
        OutputLine(blame, 0, "<head>"),
        OutputLine(
          blame,
          2,
          "<link rel=\"icon\" type=\"image/x-icon\" href=\"logo.png\">",
        ),
        OutputLine(blame, 2, "<meta charset=\"utf-8\">"),
        OutputLine(
          blame,
          2,
          "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">",
        ),
        OutputLine(
          blame,
          2,
          "<script type=\"text/javascript\" src=\"./mathjax_setup.js\"></script>",
        ),
        OutputLine(
          blame,
          2,
          "<script type=\"text/javascript\" id=\"MathJax-script\" async src=\"https://cdn.jsdelivr.net/npm/mathjax@3/es5/tex-svg.js\"></script>",
        ),
        OutputLine(blame, 0, "</head>"),
        OutputLine(blame, 0, "<body>"),
      ],
      fragment.payload
        |> core.v_get_children
        |> list.map(fn(vxml) { vp.vxml_to_html_output_lines(vxml, 2, 2) })
        |> list.flatten,
      [
        OutputLine(blame, 0, "</body>"),
        OutputLine(blame, 0, ""),
      ],
    ])
  Ok(OutputFragment(..fragment, payload: lines))
}

pub fn stub_jsx_emitter(
  fragment: OutputFragment(z, VXML),
) -> Result(OutputFragment(z, List(OutputLine)), b) {
  let blame = Ext([], "panel_emitter")
  let lines =
    list.flatten([
      [
        OutputLine(blame, 0, "import Something from \"./Somewhere\";"),
        OutputLine(blame, 0, ""),
        OutputLine(blame, 0, "const OurSuperComponent = () => {"),
        OutputLine(blame, 2, "return ("),
        OutputLine(blame, 4, "<>"),
      ],
      vp.vxmls_to_jsx_output_lines(
        fragment.payload |> core.v_get_children,
        6,
        2,
      ),
      [
        OutputLine(blame, 4, "</>"),
        OutputLine(blame, 2, ");"),
        OutputLine(blame, 0, "};"),
        OutputLine(blame, 0, ""),
        OutputLine(blame, 0, "export default OurSuperComponent;"),
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
  case
    output_dir_local_path_printer(output_dir, fragment.path, fragment.payload)
  {
    Ok(Nil) -> {
      Ok(GhostOfOutputFragment(fragment.classifier, fragment.path))
    }
    Error(file_error) -> {
      Error(
        ins(file_error) <> " on path " <> output_dir <> "/" <> fragment.path,
      )
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
  fn(String, GhostOfOutputFragment(z), Option(String)) ->
    Option(PrettifierFeedback)

pub fn run_prettier(
  in: String,
  path: String,
  check: Bool,
) -> PrettifierFeedback {
  let result =
    shellout.command(
      run: "prettier",
      in: in,
      with: [
        case check {
          True -> "--check"
          False -> "--write"
        },
        path,
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
    |> list.map(fn(s) { string.drop_start(s, 6) |> string.trim })
  let error_lines =
    lines
    |> list.filter(fn(l) { string.starts_with(l, "[error]") })
    |> list.map(fn(s) { string.drop_start(s, 7) |> string.trim })
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
    None,
  )

  let source_path = output_dir <> "/" <> ghost.path

  use #(dest_path, check) <- on.stay(case prettier_dir {
    None -> on.Stay(#(source_path, True))

    Some(dir) -> {
      let dest_path = dir <> "/" <> ghost.path
      use <- on.true_false(source_path == dest_path, fn() {
        on.Stay(#(dest_path, False))
      })
      use _ <- on.error_ok(create_dirs_on_path_to_file(dest_path), fn(e) {
        on.Return(
          Some(
            PrettifierFeedback(warnings: [], errors: [
              "could not create directories on path " <> ins(e),
            ]),
          ),
        )
      })
      case
        shellout.command(
          run: "cp",
          in: ".",
          with: [source_path, dest_path],
          opt: [],
        )
      {
        Error(#(_, msg)) -> {
          on.Return(
            Some(
              PrettifierFeedback(warnings: [], errors: [
                "unable to copy '"
                <> source_path
                <> "' to '"
                <> dest_path
                <> "':"
                <> string.trim(msg),
              ]),
            ),
          )
        }
        _ -> on.Stay(#(dest_path, False))
      }
    }
  })

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

/// Wires source ingress, parsing, filtering, desugaring, splitting, emitting,
/// writing, and optional prettification.
pub type Renderer(
  a,
  b,
  c,
  d,
  e,
  f,
  z,
  // Assembler error
  // Parser error
  // Filterer error
  // Splitter error
  // Emitter error
  // Writer error
  // VXML Fragment enum
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
    monitors: List(Monitor),
    monitor_factories: List(MonitorFactory),
    output_lines_table_default_comment_columns: Int,
    output_lines_table_default_blame_columns: Int,
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
    monitors: [],
    monitor_factories: [],
    output_lines_table_default_comment_columns: 30,
    output_lines_table_default_blame_columns: 48,
    echo_assembled_lines: False,
    echo_parsed_vxml: False,
    echo_filtered_vxml: False,
    echo_vxml_fragments: fn(_) { False },
    echo_output_lines_fragments: fn(_: OutputFragment(z, List(OutputLine))) {
      False
    },
    echo_string_fragments: fn(_: OutputFragment(z, String)) { False },
    echo_prettified_fragments: fn(_: GhostOfOutputFragment(z)) { False },
  )
}

// ************************************************************
// CommandLineAmendments
// ************************************************************

type Tracker {
  Tracker(
    printing_selector: Option(tracking.Selector),
    change_selector: Option(tracking.Selector),
    step_specs: List(PipelineStepSpec),
    interactive_mode: Bool,
    output: Option(VxmlMonitorOutput),
    include_selection_ellipses: Option(Bool),
  )
}

type VxmlMonitorOutput {
  TrackingTable(blame_columns: Option(Int), comment_columns: Option(Int))
  TrackingVerbatim
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
    tracking_monitor_factory: Option(MonitorFactory),
    dump_monitor_factory: Option(MonitorFactory),
    tracker_interactive_mode: Bool,
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
    tracking_monitor_factory: None,
    dump_monitor_factory: None,
    tracker_interactive_mode: False,
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
  let margin = string.repeat(" ", help_message_margin)
  io.println(margin <> "--help")
  io.println(
    margin <> "  -> print the basic command line options (this message)",
  )
  io.println("")
  io.println(margin <> "--esoteric")
  io.println(margin <> "  -> print advanced command line options")
  io.println("")
  io.println(margin <> "--only <string1> <string2> ...")
  io.println(
    margin
    <> "  -> restrict source to files whose paths contain at least one of",
  )
  io.println(margin <> "     the given strings as a substring")
  io.println("")
  io.println(margin <> "--only <key1=val1> <key2=val2> ...")
  io.println(
    margin <> "  -> restrict source to elements that have at least one of the",
  )
  io.println(
    margin <> "     given key-value pairs as attrs (& ancestors of such)",
  )
  io.println("")
  io.println(margin <> "--dump <step numbers>")
  io.println(
    margin <> "  -> show entire document at given pipeline step numbers; leave",
  )
  io.println(
    margin <> "     step numbers empty to output document at all steps; use",
  )
  io.println(
    margin <> "     negative indices to indicate steps from end of pipeline",
  )
  io.println("")
  io.println(
    margin <> "--track <string> [<selector arguments>] [<step ranges>]",
  )
  io.println(
    margin <> "  -> track changes near the document fragment matching <string>",
  )
  io.println(
    margin <> "     (run with '--track-help' for complete instructions)",
  )
  io.println("")
  io.println(margin <> "     gleam run -- --track \"lorem ipsum\"")
  io.println(margin <> "     gleam run -- --track src=img/23.svg +5-2")
  io.println(
    margin
    <> "     gleam run -- --track \"<> ImageRight\" -track+0 -print+-5 \\",
  )
  io.println("")
  io.println(margin <> "--track-help")
  io.println(
    margin <> "  -> print detailed '--track' instructions and examples",
  )
  io.println("")
  io.println(margin <> "--verbose")
  io.println(margin <> "  -> verbose renderer output")
  io.println("")
  io.println(margin <> "--artifacts")
  io.println(
    margin <> "  -> subset of '--verbose' to show which files were printed",
  )
  io.println("")
  io.println(margin <> "--table")
  io.println(margin <> "  -> include a printout of the pipeline steps")
  io.println("")
  io.println(
    margin <> "--times [<cols=" <> ins(default_times_table_char_width) <> ">]",
  )
  io.println(
    margin <> "  -> include performance table (how long it takes each desugarer",
  )
  io.println(margin <> "     to run) using <cols> columns")
  io.println("")
}

pub fn track_cli_usage(header: String) {
  case header {
    "" -> Nil
    _ -> io.println(header <> "\n")
  }
  let margin = string.repeat(" ", help_message_margin)
  io.println(
    margin <> "--track <string> [<selector arguments>] [<step ranges>]",
  )
  io.println(
    margin <> "  -> print document fragments when the selected VXML changes",
  )
  io.println("")
  io.println(margin <> "  <string>")
  io.println(
    margin <> "     Matches any part of a line in the printed VXML, excluding",
  )
  io.println(
    margin <> "     leading whitespace. Quote strings containing spaces.",
  )
  io.println("")
  io.println(margin <> "     gleam run -- --track \"lorem ipsum\"")
  io.println(margin <> "     gleam run -- --track src=img/23.svg")
  io.println(margin <> "     gleam run -- --track \"<> ImageRight\"")
  io.println("")
  io.println(margin <> "  selector windows")
  io.println(
    margin <> "     A signed window selects lines before and after each match.",
  )
  io.println(
    margin <> "     Write +<after>-<before>, or put the minus part first:",
  )
  io.println("")
  io.println(margin <> "       +5-2   five lines after and two before")
  io.println(margin <> "       -2+5   equivalent to +5-2")
  io.println(margin <> "       +-5    five lines on either side")
  io.println(margin <> "       -+5    equivalent to +-5")
  io.println(margin <> "       +0     only the matching line")
  io.println("")
  io.println(
    margin <> "     A nonzero one-sided form such as '+5' or '-5' is rejected.",
  )
  io.println(
    margin <> "     With no window, tracking and printing both use '-+1'.",
  )
  io.println("")
  io.println(margin <> "  tracking versus printing")
  io.println(
    margin <> "     The tracking selector decides whether the VXML changed; the",
  )
  io.println(
    margin <> "     printing selector decides which lines appear in the output.",
  )
  io.println("")
  io.println(
    margin
    <> "     One unlabeled window is used for both tracking and printing.",
  )
  io.println(
    margin <> "     With two, the first tracks and the second prints. The roles",
  )
  io.println(
    margin <> "     can instead be labeled '-track' and '-print' explicitly.",
  )
  io.println("")
  io.println(margin <> "       +0 +-5                 track +0; print +-5")
  io.println(margin <> "       -track+0 -print+-5     the explicit equivalent")
  io.println("")
  io.println(
    margin
    <> "     If only '-track' is present, its complete selector is copied",
  )
  io.println(
    margin <> "     to '-print'. If only '-print' is present, tracking defaults",
  )
  io.println(margin <> "     to '-track-+1'.")
  io.println("")
  io.println(margin <> "  selector modifiers")
  io.println(margin <> "     with-ancestors            include ancestor tags")
  io.println(
    margin <> "     with-elder-siblings       also include elder sibling tags",
  )
  io.println(
    margin <> "     with-ancestor-attrs       include ancestor attributes",
  )
  io.println(
    margin <> "     with-attrs                alias for with-ancestor-attrs",
  )
  io.println(
    margin <> "     with-elder-sibling-attrs  also include elder sibling attrs",
  )
  io.println("")
  io.println(
    margin <> "     Modifiers before the first labeled window apply to both",
  )
  io.println(
    margin <> "     selectors. Modifiers after a label apply only to that one.",
  )
  io.println("")
  io.println(
    margin <> "       with-ancestors -track+0 -print+-5 with-ancestor-attrs",
  )
  io.println("")
  io.println(margin <> "  pipeline step ranges")
  io.println(
    margin <> "     Leave step ranges empty to observe changes at every step.",
  )
  io.println(margin <> "     Otherwise, use absolute step numbers and ranges:")
  io.println("")
  io.println(margin <> "       50        step 50")
  io.println(margin <> "       50-60     steps 50 through 60")
  io.println(margin <> "       50-       step 50 through the end")
  io.println(margin <> "       -5--1     the final five steps")
  io.println(margin <> "       !123      force output at step 123")
  io.println("")
  io.println(
    margin
    <> "     A leading '!' forces output even if the tracked fragment did",
  )
  io.println(
    margin <> "     not change. Negative absolute indices count from the end.",
  )
  io.println("")
  io.println(
    margin <> "     A desugarer name selects its occurrences in the pipeline.",
  )
  io.println(
    margin <> "     Signed offsets following the name are relative to each",
  )
  io.println(margin <> "     occurrence:")
  io.println("")
  io.println(margin <> "       rename          each 'rename' step")
  io.println(
    margin <> "       rename-5        five steps before through rename",
  )
  io.println(margin <> "       rename+5        rename through five steps after")
  io.println(margin <> "       rename-2+3      two before through three after")
  io.println(margin <> "       rename+2+5      two through five steps after")
  io.println("")
  io.println(
    margin <> "     Prefix an absolute range with '!' when its text could be",
  )
  io.println(
    margin
    <> "     mistaken for a desugarer-relative range, or to force output.",
  )
  io.println("")
  io.println(margin <> "  output formatting")
  io.println(
    margin <> "     -verbatim  print raw selected VXML without the blame table",
  )
  io.println(margin <> "     -cc<n>     use n columns for blame comments")
  io.println(margin <> "     -bc<n>     use n columns for blame provenance")
  io.println(margin <> "     -no-ellipses  suppress lines marking omitted VXML")
  io.println("")
  io.println(
    margin <> "     A column count of zero suppresses that table column.",
  )
  io.println(margin <> "     Column options have no effect with '-verbatim'.")
  io.println("")
  io.println(margin <> "       gleam run -- --track src=img/23.svg -cc10 -bc20")
  io.println(
    margin <> "       gleam run -- --track \"<> ImageRight\" -verbatim",
  )
  io.println("")
  io.println(margin <> "  interactive mode")
  io.println(
    margin <> "     Add '-i' to pause after each monitor output. At the prompt:",
  )
  io.println(margin <> "       <enter>  continue to the next output")
  io.println(margin <> "       <n>      skip pauses for the next n outputs")
  io.println(margin <> "       e        leave interactive mode")
  io.println(margin <> "       c        cancel the pipeline")
  io.println("")
  io.println(margin <> "  complete examples")
  io.println("")
  io.println(
    margin <> "     gleam run -- --track \"lorem ipsum\" +0 +-5 50-100",
  )
  io.println(
    margin <> "     gleam run -- --track \"<> ImageRight\" -track+0 -print+-5",
  )
  io.println(margin <> "       with-ancestor-attrs rename-2+2 !-1")
  io.println("")
}

pub fn advanced_cli_usage(header: String) {
  let margin = string.repeat(" ", help_message_margin)
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
  io.println(
    margin <> "  -> run prettier --check on each output file (read-only)",
  )
  io.println("")
  io.println(margin <> "--prettier <dir>")
  io.println(
    margin
    <> "  -> run prettier --write, outputting to <dir> instead of output_dir",
  )
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
  io.println(
    margin <> "  -> print the parsed VXML filtered for key-value pairs",
  )
  io.println("")
  io.println(margin <> "--echo-vxml-fragments <subpath1> <subpath2> ...")
  io.println(
    margin
    <> "  -> echo fragments whose paths contain one of the given subpaths",
  )
  io.println(
    margin <> "     before conversion to output lines, list none to match all",
  )
  io.println("")
  io.println(margin <> "--echo-ol-fragments <subpath1> <subpath2> ...")
  io.println(
    margin
    <> "  -> echo fragments whose paths contain one of the given subpaths",
  )
  io.println(
    margin <> "     after conversion to output lines, list none to match all",
  )
  io.println("")
  io.println(margin <> "--track-steps")
  io.println(
    margin
    <> "  -> (re)set the tracking step numbers of the current tracker, if",
  )
  io.println(
    margin <> "     any; takes arguments in the same form as the <step numbers>",
  )
  io.println(
    margin <> "     sub-option of '--track' (e.g., '50-60 !123-125 !-1')",
  )
  io.println("")
}

fn print_with_terminal_blank_line(message: String) {
  let message = string.trim_end(message)
  case message {
    "" -> Nil
    _ -> {
      io.println(message)
      io.println("")
    }
  }
}

/// Print requested help and remove help flags from command-line arguments.
///
/// Each requested help section is printed at most once. `local_cli_usage` is
/// evaluated and appended only when `--help` is present.
pub fn handle_help_requests(
  args: List(String),
  local_cli_usage: fn() -> String,
) -> #(List(String), Bool) {
  let basic =
    list.contains(args, "--help")
    || list.contains(args, "-help")
    || list.contains(args, "-h")
  let esoteric = list.contains(args, "--esoteric")
  let track = list.contains(args, "--track-help")

  case basic {
    True -> {
      basic_cli_usage("'gleam run' command line options (basic):")
      case local_cli_usage() {
        "" -> Nil
        local_usage -> local_usage |> print_with_terminal_blank_line
      }
    }
    False -> Nil
  }
  case esoteric {
    True -> advanced_cli_usage("'gleam run' command line options (esoteric):")
    False -> Nil
  }
  case track {
    True -> track_cli_usage("'gleam run -- --track' command line options:")
    False -> Nil
  }

  let args =
    list.filter(args, fn(arg) {
      arg != "--help"
      && arg != "-help"
      && arg != "-h"
      && arg != "--esoteric"
      && arg != "--track-help"
    })
  #(args, basic || esoteric || track)
}

/// Run requested local-desugarer maintenance and remove its command-line flags.
///
/// Each operation runs at most once. `--desugarers` requests blame
/// renumbering, local-library generation, and all local desugarer tests.
pub fn handle_maintenance_requests(
  args: List(String),
  local_desugarer_tests: List(fn() -> core.AssertiveTestCollection),
) -> Result(#(List(String), Bool), String) {
  let renumber =
    list.contains(args, "--renumber") || list.contains(args, "--desugarers")
  let generate =
    list.contains(args, "--generate")
    || list.contains(args, "--regenerate")
    || list.contains(args, "--desugarers")
  use #(args, requested_test_names) <- result.try(
    extract_desugarer_test_request(args),
  )
  let requested_test_names = case
    requested_test_names,
    list.contains(args, "--desugarers")
  {
    None, True -> Some([])
    requested, _ -> requested
  }
  let tests_requested = option.is_some(requested_test_names)

  let #(maintenance_result, printed) =
    perform_requested_maintenance(
      renumber,
      generate,
      requested_test_names,
      local_desugarer_tests,
      False,
    )
  case printed {
    True -> io.println("")
    False -> Nil
  }
  use _ <- result.try(maintenance_result)

  let args =
    list.filter(args, fn(arg) {
      arg != "--renumber"
      && arg != "--generate"
      && arg != "--regenerate"
      && arg != "--desugarers"
    })
  Ok(#(args, renumber || generate || tests_requested))
}

fn perform_requested_maintenance(
  renumber: Bool,
  generate: Bool,
  requested_test_names: Option(List(String)),
  local_desugarer_tests: List(fn() -> core.AssertiveTestCollection),
  content_printed: Bool,
) -> #(Result(Nil, String), Bool) {
  case renumber {
    True ->
      case local_desugarer_blame_renumberer.perform() {
        Error(message) -> #(Error(message), content_printed)
        Ok(Nil) ->
          perform_requested_maintenance(
            False,
            generate,
            requested_test_names,
            local_desugarer_tests,
            True,
          )
      }
    False ->
      case generate {
        True ->
          case local_desugarer_generator.perform() {
            Error(message) -> #(Error(message), content_printed)
            Ok(Nil) ->
              perform_requested_maintenance(
                False,
                False,
                requested_test_names,
                local_desugarer_tests,
                True,
              )
          }
        False ->
          case requested_test_names {
            None -> #(Ok(Nil), content_printed)
            Some(names) -> {
              case content_printed {
                True -> io.println("")
                False -> Nil
              }
              #(
                testing.test_desugarers_content(local_desugarer_tests, names),
                True,
              )
            }
          }
      }
  }
}

fn extract_desugarer_test_request(
  args: List(String),
) -> Result(#(List(String), Option(List(String))), String) {
  extract_desugarer_test_request_loop(args, [])
}

fn extract_desugarer_test_request_loop(
  args: List(String),
  reversed_before: List(String),
) -> Result(#(List(String), Option(List(String))), String) {
  case args {
    [] -> Ok(#(list.reverse(reversed_before), None))
    [arg, ..after] ->
      case is_desugarer_test_option(arg) {
        True ->
          case list.any(after, is_desugarer_test_option) {
            True -> Error("Duplicate desugarer-test options.")
            False -> {
              let #(names, after) =
                list.split_while(after, fn(arg) {
                  !string.starts_with(arg, "-")
                })
              Ok(#(
                list.append(list.reverse(reversed_before), after),
                Some(names),
              ))
            }
          }
        False ->
          extract_desugarer_test_request_loop(after, [arg, ..reversed_before])
      }
  }
}

fn is_desugarer_test_option(arg: String) -> Bool {
  case arg {
    "--desugarer-tests" | "--test-desugarers" -> True
    _ -> False
  }
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
  use list_key_values <- on.error_ok(double_dash_keys(arguments), fn(bad_key) {
    Error(ExpectedDoubleDashString(bad_key))
  })

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
          basic_cli_usage("renderer common command line options:")
          case list.is_empty(values) {
            True -> Ok(CommandLineAmendments(..amendments, help: True))
            False -> Error(UnexpectedArgumentsToOption("option"))
          }
        }

        "--track-help" ->
          case list.is_empty(values) {
            True -> {
              track_cli_usage("renderer '--track' command line instructions:")
              Ok(CommandLineAmendments(..amendments, help: True))
            }
            False -> Error(UnexpectedArgumentsToOption("--track-help"))
          }

        "--esoteric" -> {
          advanced_cli_usage("renderer advanced command line options:")
          case list.is_empty(values) {
            True -> Ok(CommandLineAmendments(..amendments, help: True))
            False -> Error(UnexpectedArgumentsToOption("option"))
          }
        }

        "--times" -> {
          use arg <- on.ok(parse_times_args(values))
          Ok(
            CommandLineAmendments(
              ..amendments,
              times: arg |> core.with_default(default_times_table_char_width),
            ),
          )
        }

        "--input-dir" -> {
          case values {
            [one] ->
              Ok(
                CommandLineAmendments(
                  ..amendments,
                  input_dir: Some(one |> core.drop_ending_slash),
                ),
              )
            [] -> Error(MissingArgumentToOption("--input-dir"))
            _ -> Error(TooManyArgumentsToOption("--input-dir"))
          }
        }

        "--output-dir" -> {
          case values {
            [one] ->
              Ok(
                CommandLineAmendments(
                  ..amendments,
                  output_dir: Some(one |> core.drop_ending_slash),
                ),
              )
            [] -> Error(MissingArgumentToOption("--output-dir"))
            _ -> Error(TooManyArgumentsToOption("--output-dir"))
          }
        }

        "--only" -> {
          let args =
            values
            |> list.map(parse_attr_value_args_in_filename)
            |> list.flatten()

          CommandLineAmendments(
            ..amendments,
            warnings: Some(option.unwrap(amendments.warnings, False)),
          )
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
            [] ->
              Ok(
                CommandLineAmendments(
                  ..amendments,
                  prettier: Some(PrettifierOff),
                ),
              )
            _ -> Error(UnexpectedArgumentsToOption("--prettier-off"))
          }

        "--prettier-on" ->
          case values {
            [] ->
              Ok(
                CommandLineAmendments(
                  ..amendments,
                  prettier: Some(PrettifierOverwriteOutputDir),
                ),
              )
            _ -> Error(UnexpectedArgumentsToOption("--prettier-on"))
          }

        "--prettier-check" ->
          case values {
            [] ->
              Ok(
                CommandLineAmendments(
                  ..amendments,
                  prettier: Some(PrettifierToBespokeDir(None)),
                ),
              )
            _ -> Error(UnexpectedArgumentsToOption("--prettier-check"))
          }

        "--prettier" ->
          case values {
            [dir] ->
              Ok(
                CommandLineAmendments(
                  ..amendments,
                  prettier: Some(PrettifierToBespokeDir(Some(dir))),
                ),
              )
            _ -> Error(UnexpectedArgumentsToOption("--prettier"))
          }

        "--track" -> {
          use tracker <- on.ok(parse_track_args(values))
          Ok(
            CommandLineAmendments(
              ..amendments,
              tracking_monitor_factory: Some(join_tracking_monitor_factory(
                amendments.tracking_monitor_factory,
                tracker,
              )),
              tracker_interactive_mode: {
                amendments.tracker_interactive_mode || tracker.interactive_mode
              },
            ),
          )
        }

        "--track-steps" -> {
          use tracker <- on.ok(parse_track_steps_args(values))
          Ok(
            CommandLineAmendments(
              ..amendments,
              tracking_monitor_factory: Some(join_tracking_monitor_factory(
                amendments.tracking_monitor_factory,
                tracker,
              )),
              tracker_interactive_mode: {
                amendments.tracker_interactive_mode || tracker.interactive_mode
              },
            ),
          )
        }

        "--dump" -> {
          use #(specs, output) <- on.ok(parse_dump_args(values))
          case amendments.dump_monitor_factory {
            None ->
              Ok(
                CommandLineAmendments(
                  ..amendments,
                  dump_monitor_factory: Some(DumpMonitorFactory(specs, output)),
                ),
              )
            _ -> Error(DuplicateOption(option))
          }
        }

        "--echo-assembled" ->
          case list.is_empty(values) {
            True ->
              Ok(CommandLineAmendments(..amendments, echo_assembled: True))
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
            True ->
              Ok(
                CommandLineAmendments(
                  ..amendments,
                  vxml_fragments_local_paths_to_echo: Some(values),
                ),
              )
            False -> Error(UnexpectedArgumentsToOption(option))
          }

        "--echo-ol-fragments" ->
          case list.is_empty(values) {
            True ->
              Ok(
                CommandLineAmendments(
                  ..amendments,
                  output_lines_fragments_local_paths_to_echo: Some(values),
                ),
              )
            False -> Error(UnexpectedArgumentsToOption(option))
          }

        "--succinct" ->
          case list.is_empty(values) {
            True ->
              Ok(CommandLineAmendments(..amendments, verbose: Some(False)))
            False -> Error(UnexpectedArgumentsToOption(option))
          }

        "--verbose" ->
          case list.is_empty(values) {
            True -> Ok(CommandLineAmendments(..amendments, verbose: Some(True)))
            False -> Error(UnexpectedArgumentsToOption(option))
          }

        "--artifacts" ->
          case list.is_empty(values) {
            True ->
              Ok(CommandLineAmendments(..amendments, artifacts: Some(True)))
            False -> Error(UnexpectedArgumentsToOption(option))
          }

        "--no-artifacts" ->
          case list.is_empty(values) {
            True ->
              Ok(CommandLineAmendments(..amendments, artifacts: Some(False)))
            False -> Error(UnexpectedArgumentsToOption(option))
          }

        "--warnings" ->
          case list.is_empty(values) {
            True ->
              Ok(CommandLineAmendments(..amendments, warnings: Some(True)))
            False -> Error(UnexpectedArgumentsToOption(option))
          }

        "--no-warnings" ->
          case list.is_empty(values) {
            True ->
              Ok(CommandLineAmendments(..amendments, warnings: Some(False)))
            False -> Error(UnexpectedArgumentsToOption(option))
          }

        _ -> {
          case list.contains(user_keys, option) {
            True ->
              Ok(
                CommandLineAmendments(
                  ..amendments,
                  user_args: dict.insert(amendments.user_args, option, values),
                ),
              )
            False -> Error(UnknownOptionArgument(option))
          }
        }
      }
    },
  )
}

// General command-line tokenization

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

// --only parsing

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
        |> list.map(fn(a) { a.0 }),
    ),
    only_key_vals: list.append(
      amendments.only_key_vals,
      args
        |> list.filter(fn(a) { a.0 == "" && { a.1 != "" || a.2 != "" } })
        |> list.map(fn(a) { #(a.1, a.2) }),
    ),
    only_path_key_vals: list.append(
      amendments.only_path_key_vals,
      args
        |> list.filter(fn(a) { a.0 != "" && { a.1 != "" || a.2 != "" } }),
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

// --track, --track-steps, and --dump parsing

type SelectorLineWindow {
  SelectorLineWindow(lines_after: Int, lines_before: Int)
}

type AbsoluteStepRange {
  ClosedAbsoluteStepRange(first: Int, last: Int)
  AbsoluteStepsFrom(first: Int)
}

type DesugarerRelativeStepRange {
  DesugarerRelativeStepRange(
    desugarer_name: String,
    first_offset: Int,
    last_offset: Int,
  )
}

type PipelineStepRange {
  AbsoluteSteps(AbsoluteStepRange)
  DesugarerRelativeSteps(DesugarerRelativeStepRange)
}

type PipelineStepOutputMode {
  OnChange
  Forced
}

type PipelineStepSpec {
  PipelineStepSpec(
    range: PipelineStepRange,
    output_mode: PipelineStepOutputMode,
  )
}

fn parse_selector_line_window(s: String) -> Result(SelectorLineWindow, Nil) {
  case string.starts_with(s, "+-"), string.starts_with(s, "-+") {
    True, _ ->
      int.parse(string.drop_start(s, 2))
      |> result.map(fn(size) { SelectorLineWindow(size, size) })
    _, True ->
      int.parse(string.drop_start(s, 2))
      |> result.map(fn(size) { SelectorLineWindow(size, size) })
    _, _ -> parse_asymmetric_selector_line_window(s)
  }
}

fn parse_asymmetric_selector_line_window(
  s: String,
) -> Result(SelectorLineWindow, Nil) {
  case string.starts_with(s, "+"), string.starts_with(s, "-") {
    True, _ -> {
      let s = string.drop_start(s, 1)
      case string.split_once(s, "-") {
        Ok(#(before, after)) -> {
          case int.parse(before), int.parse(after) {
            Ok(p), Ok(m) -> Ok(SelectorLineWindow(p, m))
            _, _ -> Error(Nil)
          }
        }
        _ ->
          case int.parse(s) {
            Ok(0) -> Ok(SelectorLineWindow(0, 0))
            _ -> Error(Nil)
          }
      }
    }

    _, True -> {
      let s = string.drop_start(s, 1)
      case string.split_once(s, "+") {
        Ok(#(before, after)) -> {
          case int.parse(before), int.parse(after) {
            Ok(m), Ok(p) -> Ok(SelectorLineWindow(p, m))
            _, _ -> Error(Nil)
          }
        }
        _ ->
          case int.parse(s) {
            Ok(0) -> Ok(SelectorLineWindow(0, 0))
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

pub fn extract_desugarer_name(input: String) -> #(String, String) {
  let assert Ok(re) = regexp.from_string("^([a-z_][a-z0-9_]*)(.*)")
  case regexp.scan(with: re, content: input) {
    [regexp.Match(_, [Some(prefix), rest, ..])] -> #(
      prefix,
      option.unwrap(rest, ""),
    )
    _ -> #("", input)
  }
}

fn regex_captures(pattern: String, input: String) -> List(Option(String)) {
  let assert Ok(regex) = regexp.from_string(pattern)
  case regexp.scan(with: regex, content: input) {
    [regexp.Match(_, captures)] -> captures
    _ -> []
  }
}

fn parse_absolute_step_range(
  input: String,
) -> Result(AbsoluteStepRange, CommandLineError) {
  case regex_captures("^(-?[0-9]+)-(-?[0-9]+)$", input) {
    [Some(first), Some(last), ..] -> {
      let assert Ok(first) = int.parse(first)
      let assert Ok(last) = int.parse(last)
      Ok(ClosedAbsoluteStepRange(first, last))
    }
    _ ->
      case regex_captures("^(-?[0-9]+)-$", input) {
        [Some(first), ..] -> {
          let assert Ok(first) = int.parse(first)
          Ok(AbsoluteStepsFrom(first))
        }
        _ ->
          case int.parse(input) {
            Ok(step) -> Ok(ClosedAbsoluteStepRange(step, step))
            Error(_) ->
              Error(StepNoValues(
                "unable to parse absolute step range '" <> input <> "'",
              ))
          }
      }
  }
}

fn parse_signed_offset(input: String) -> Result(Int, Nil) {
  case string.starts_with(input, "+") {
    True -> int.parse(string.drop_start(input, 1))
    False -> int.parse(input)
  }
}

fn parse_desugarer_relative_step_range(
  input: String,
) -> Result(DesugarerRelativeStepRange, CommandLineError) {
  let #(name, suffix) = extract_desugarer_name(input)
  use _ <- on.stay(case name {
    "" ->
      on.Return(
        Error(StepNoValues(
          "unable to parse desugarer-relative step range '" <> input <> "'",
        )),
      )
    _ -> on.Stay(Nil)
  })
  case suffix {
    "" -> Ok(DesugarerRelativeStepRange(name, 0, 0))
    _ ->
      case regex_captures("^([+-][0-9]+)([+-][0-9]+)?$", suffix) {
        [Some(first), ..] as captures -> {
          let assert Ok(first) = parse_signed_offset(first)
          let second = case list.drop(captures, 1) {
            [Some(second), ..] -> {
              let assert Ok(second) = parse_signed_offset(second)
              second
            }
            _ -> 0
          }
          Ok(DesugarerRelativeStepRange(
            name,
            int.min(first, second),
            int.max(first, second),
          ))
        }
        _ ->
          Error(StepNoValues(
            "unable to parse desugarer-relative step range '" <> input <> "'",
          ))
      }
  }
}

fn parse_pipeline_step_spec(
  input: String,
) -> Result(PipelineStepSpec, CommandLineError) {
  let #(mode, payload) = case string.starts_with(input, "!") {
    True -> #(Forced, string.drop_start(input, 1))
    False -> #(OnChange, input)
  }
  use _ <- on.stay(case payload {
    "" -> on.Return(Error(StepNoValues("missing step range after '!'")))
    _ -> on.Stay(Nil)
  })
  case string.starts_with(payload, "+") {
    True ->
      Error(StepNoValues(
        "absolute step ranges cannot start with '+' [" <> input <> "]",
      ))
    False -> {
      let #(name, _) = extract_desugarer_name(payload)
      case name {
        "" ->
          parse_absolute_step_range(payload)
          |> result.map(fn(range) {
            PipelineStepSpec(AbsoluteSteps(range), mode)
          })
        _ ->
          parse_desugarer_relative_step_range(payload)
          |> result.map(fn(range) {
            PipelineStepSpec(DesugarerRelativeSteps(range), mode)
          })
      }
    }
  }
}

fn parse_pipeline_step_specs(
  values: List(String),
) -> Result(List(PipelineStepSpec), CommandLineError) {
  list.try_map(values, parse_pipeline_step_spec)
}

type SelectorTarget {
  TrackSelector
  PrintSelector
}

type SelectorDefinition {
  SelectorDefinition(
    target: SelectorTarget,
    window: SelectorLineWindow,
    modifiers: List(String),
  )
}

type SelectorNormalizationState {
  SelectorNormalizationState(
    remaining_anchors: List(#(SelectorTarget, SelectorLineWindow)),
    common_modifiers: List(String),
    current_definition: Option(SelectorDefinition),
    completed_definitions: List(SelectorDefinition),
  )
}

fn selector_modifier(input: String) -> Bool {
  let input = string.replace(input, "-with", "with")
  list.contains(
    [
      "with-ancestors",
      "with-elder-siblings",
      "with-attrs",
      "with-attributes",
      "with-ancestor-attrs",
      "with-ancestor-attributes",
      "with-elder-sibling-attrs",
      "with-elder-sibling-attributes",
    ],
    input,
  )
}

fn parse_selector_anchor(
  input: String,
) -> Result(
  Option(#(Option(SelectorTarget), SelectorLineWindow)),
  CommandLineError,
) {
  let #(target, payload) = case
    string.starts_with(input, "-track"),
    string.starts_with(input, "-print")
  {
    True, _ -> #(Some(TrackSelector), string.drop_start(input, 6))
    _, True -> #(Some(PrintSelector), string.drop_start(input, 6))
    _, _ -> #(None, input)
  }
  case parse_selector_line_window(payload) {
    Ok(window) -> Ok(Some(#(target, window)))
    Error(_) ->
      case target {
        Some(_) ->
          Error(SelectorValues("invalid selector line window '" <> input <> "'"))
        None -> Ok(None)
      }
  }
}

type VxmlMonitorOutputArguments {
  VxmlMonitorOutputArguments(
    verbatim: Bool,
    blame_columns: Option(Int),
    comment_columns: Option(Int),
    remaining: List(String),
  )
}

fn parse_tracking_column_count(
  option: String,
  value: String,
) -> Result(Int, CommandLineError) {
  use columns <- on.error_ok(int.parse(value), fn(_) {
    Error(SelectorValues("invalid column count in '" <> option <> value <> "'"))
  })
  case columns >= 0 {
    True -> Ok(columns)
    False ->
      Error(SelectorValues(
        "column count cannot be negative in '" <> option <> value <> "'",
      ))
  }
}

fn parse_vxml_monitor_output_arguments(
  values: List(String),
) -> Result(#(VxmlMonitorOutput, List(String)), CommandLineError) {
  use parsed <- on.ok(
    list.try_fold(
      values,
      VxmlMonitorOutputArguments(False, None, None, []),
      fn(acc, value) {
        case
          value == "-verbatim",
          string.starts_with(value, "-bc"),
          string.starts_with(value, "-cc")
        {
          True, _, _ ->
            case acc.verbatim {
              True -> Error(SelectorValues("duplicate '-verbatim' option"))
              False -> Ok(VxmlMonitorOutputArguments(..acc, verbatim: True))
            }
          _, True, _ ->
            case acc.blame_columns {
              Some(_) -> Error(SelectorValues("duplicate '-bc' option"))
              None -> {
                use columns <- on.ok(parse_tracking_column_count(
                  "-bc",
                  string.drop_start(value, 3),
                ))
                Ok(
                  VxmlMonitorOutputArguments(
                    ..acc,
                    blame_columns: Some(columns),
                  ),
                )
              }
            }
          _, _, True ->
            case acc.comment_columns {
              Some(_) -> Error(SelectorValues("duplicate '-cc' option"))
              None -> {
                use columns <- on.ok(parse_tracking_column_count(
                  "-cc",
                  string.drop_start(value, 3),
                ))
                Ok(
                  VxmlMonitorOutputArguments(
                    ..acc,
                    comment_columns: Some(columns),
                  ),
                )
              }
            }
          _, _, _ ->
            Ok(
              VxmlMonitorOutputArguments(
                ..acc,
                remaining: list.append(acc.remaining, [value]),
              ),
            )
        }
      },
    ),
  )

  case parsed.verbatim {
    True -> Ok(#(TrackingVerbatim, parsed.remaining))
    False ->
      Ok(#(
        TrackingTable(parsed.blame_columns, parsed.comment_columns),
        parsed.remaining,
      ))
  }
}

fn parse_track_ellipsis_argument(
  values: List(String),
) -> Result(#(Bool, List(String)), CommandLineError) {
  use #(found, remaining) <- on.ok(
    list.try_fold(values, #(False, []), fn(acc, value) {
      case value == "-no-ellipses", acc.0 {
        True, True -> Error(SelectorValues("duplicate '-no-ellipses' option"))
        True, False -> Ok(#(True, acc.1))
        False, _ -> Ok(#(acc.0, list.append(acc.1, [value])))
      }
    }),
  )
  Ok(#(!found, remaining))
}

fn partition_track_arguments(
  values: List(String),
) -> Result(#(Bool, List(String), List(PipelineStepSpec)), CommandLineError) {
  list.try_fold(values, #(False, [], []), fn(acc, value) {
    case value {
      "-i" -> Ok(#(True, acc.1, acc.2))
      _ -> {
        use anchor <- on.ok(parse_selector_anchor(value))
        case anchor != None || selector_modifier(value) {
          True -> Ok(#(acc.0, list.append(acc.1, [value]), acc.2))
          False -> {
            use spec <- on.ok(parse_pipeline_step_spec(value))
            Ok(#(acc.0, acc.1, list.append(acc.2, [spec])))
          }
        }
      }
    }
  })
}

fn assign_selector_targets(
  anchors: List(#(Option(SelectorTarget), SelectorLineWindow)),
) -> Result(List(#(SelectorTarget, SelectorLineWindow)), CommandLineError) {
  case anchors {
    [] -> Ok([])
    [#(None, window)] -> Ok([#(TrackSelector, window)])
    [#(Some(target), window)] -> Ok([#(target, window)])
    [#(None, first), #(None, second)] ->
      Ok([#(TrackSelector, first), #(PrintSelector, second)])
    [#(Some(TrackSelector), first), #(None, second)] ->
      Ok([#(TrackSelector, first), #(PrintSelector, second)])
    [#(Some(PrintSelector), first), #(None, second)] ->
      Ok([#(PrintSelector, first), #(TrackSelector, second)])
    [#(None, first), #(Some(TrackSelector), second)] ->
      Ok([#(PrintSelector, first), #(TrackSelector, second)])
    [#(None, first), #(Some(PrintSelector), second)] ->
      Ok([#(TrackSelector, first), #(PrintSelector, second)])
    [#(Some(first_target), first), #(Some(second_target), second)] ->
      case first_target == second_target {
        True -> Error(SelectorValues("duplicate -track or -print selector"))
        False -> Ok([#(first_target, first), #(second_target, second)])
      }
    _ -> Error(SelectorValues("--track accepts at most two selector windows"))
  }
}

fn normalize_selector_definitions(
  values: List(String),
) -> Result(#(SelectorDefinition, SelectorDefinition), CommandLineError) {
  use anchors <- on.ok(
    values
    |> list.try_fold([], fn(anchors, value) {
      use anchor <- on.ok(parse_selector_anchor(value))
      case anchor {
        None -> Ok(anchors)
        Some(anchor) -> Ok(list.append(anchors, [anchor]))
      }
    }),
  )
  use assigned <- on.ok(assign_selector_targets(anchors))
  let default_window = SelectorLineWindow(1, 1)
  case assigned {
    [] -> {
      let track = SelectorDefinition(TrackSelector, default_window, values)
      Ok(#(track, SelectorDefinition(PrintSelector, default_window, values)))
    }
    _ -> {
      let assert Ok(SelectorNormalizationState(
        remaining_anchors: [],
        common_modifiers: common,
        current_definition: current,
        completed_definitions: definitions,
      )) =
        list.try_fold(
          values,
          SelectorNormalizationState(assigned, [], None, []),
          fn(acc, value) {
            use anchor <- on.ok(parse_selector_anchor(value))
            case anchor {
              None ->
                case acc.current_definition {
                  None ->
                    Ok(
                      SelectorNormalizationState(
                        ..acc,
                        common_modifiers: list.append(acc.common_modifiers, [
                          value,
                        ]),
                      ),
                    )
                  Some(definition) ->
                    Ok(
                      SelectorNormalizationState(
                        ..acc,
                        current_definition: Some(
                          SelectorDefinition(
                            ..definition,
                            modifiers: list.append(definition.modifiers, [value]),
                          ),
                        ),
                      ),
                    )
                }
              Some(_) -> {
                let assert [#(target, window), ..remaining] =
                  acc.remaining_anchors
                let definitions = case acc.current_definition {
                  None -> acc.completed_definitions
                  Some(definition) ->
                    list.append(acc.completed_definitions, [definition])
                }
                Ok(SelectorNormalizationState(
                  remaining_anchors: remaining,
                  common_modifiers: acc.common_modifiers,
                  current_definition: Some(
                    SelectorDefinition(target, window, []),
                  ),
                  completed_definitions: definitions,
                ))
              }
            }
          },
        )
      let definitions = case current {
        None -> definitions
        Some(definition) -> list.append(definitions, [definition])
      }
      let definitions =
        list.map(definitions, fn(definition) {
          SelectorDefinition(
            ..definition,
            modifiers: list.append(common, definition.modifiers),
          )
        })
      case definitions {
        [SelectorDefinition(TrackSelector, window, modifiers)] ->
          Ok(#(
            SelectorDefinition(TrackSelector, window, modifiers),
            SelectorDefinition(PrintSelector, window, modifiers),
          ))
        [SelectorDefinition(PrintSelector, window, modifiers)] ->
          Ok(#(
            SelectorDefinition(TrackSelector, default_window, common),
            SelectorDefinition(PrintSelector, window, modifiers),
          ))
        [first, second] ->
          case first.target {
            TrackSelector -> Ok(#(first, second))
            PrintSelector -> Ok(#(second, first))
          }
        _ -> Error(SelectorValues("unable to normalize selector arguments"))
      }
    }
  }
}

fn selector_from_definition(
  base_selector: Selector,
  definition: SelectorDefinition,
) -> Result(Selector, CommandLineError) {
  let values =
    list.map(definition.modifiers, fn(value) {
      string.replace(value, "-with", "with")
    })
  let #(with_ancestors, values) = core.delete(values, "with-ancestors")
  let #(with_elder_siblings, values) =
    core.delete(values, "with-elder-siblings")
  let #(with_attrs, values) = core.delete(values, "with-attrs")
  let #(with_attrs_v2, values) = core.delete(values, "with-attributes")
  let #(with_ancestor_attrs, values) =
    core.delete(values, "with-ancestor-attrs")
  let #(with_ancestor_attrs_v2, values) =
    core.delete(values, "with-ancestor-attributes")
  let #(with_elder_sibling_attrs, values) =
    core.delete(values, "with-elder-sibling-attrs")
  let #(with_elder_sibling_attrs_v2, values) =
    core.delete(values, "with-elder-sibling-attributes")
  use _ <- on.stay(case values {
    [] -> on.Stay(Nil)
    _ ->
      on.Return(
        Error(SelectorValues("unexpected selector arguments " <> ins(values))),
      )
  })
  let with_attrs = with_attrs || with_attrs_v2
  let with_elder_sibling_attrs =
    with_elder_sibling_attrs || with_elder_sibling_attrs_v2 || with_attrs
  let with_ancestor_attrs =
    with_ancestor_attrs || with_ancestor_attrs_v2 || with_elder_sibling_attrs
  let with_elder_siblings = with_elder_siblings || with_elder_sibling_attrs
  let with_ancestors =
    with_ancestors || with_elder_siblings || with_ancestor_attrs
  let selector =
    base_selector
    |> tracking.extend_selector_up(definition.window.lines_before)
    |> tracking.extend_selector_down(definition.window.lines_after)
  case with_ancestors {
    False -> Ok(selector)
    True ->
      Ok(tracking.extend_selector_to_ancestors(
        selector,
        with_elder_siblings,
        with_ancestor_attrs,
        with_elder_sibling_attrs,
      ))
  }
}

fn parse_track_args(values: List(String)) -> Result(Tracker, CommandLineError) {
  use first_payload, values <- on.empty_nonempty(values, fn() {
    Error(SelectorValues("missing 1st argument"))
  })

  let assert True = first_payload != ""
  use #(include_selection_ellipses, values) <- on.ok(
    parse_track_ellipsis_argument(values),
  )
  use #(output, values) <- on.ok(parse_vxml_monitor_output_arguments(values))
  use #(with_enter, selector_arguments, step_specs) <- on.ok(
    partition_track_arguments(values),
  )
  use #(track_definition, print_definition) <- on.ok(
    normalize_selector_definitions(selector_arguments),
  )
  let base_selector = sl.verbatim(first_payload)
  use change_selector <- on.ok(selector_from_definition(
    base_selector,
    track_definition,
  ))
  use printing_selector <- on.ok(selector_from_definition(
    base_selector,
    print_definition,
  ))

  Ok(Tracker(
    printing_selector: Some(printing_selector),
    change_selector: Some(change_selector),
    step_specs: step_specs,
    interactive_mode: with_enter,
    output: Some(output),
    include_selection_ellipses: Some(include_selection_ellipses),
  ))
}

fn parse_track_steps_args(
  values: List(String),
) -> Result(Tracker, CommandLineError) {
  let #(with_enter, values) = core.delete(values, "-i")
  use step_specs <- on.ok(parse_pipeline_step_specs(values))
  Ok(Tracker(
    printing_selector: None,
    change_selector: None,
    step_specs: step_specs,
    interactive_mode: with_enter,
    output: None,
    include_selection_ellipses: None,
  ))
}

fn join_trackers(pm1: Option(Tracker), pm2: Tracker) -> Tracker {
  use pm1 <- on.eager_none_some(pm1, pm2)
  Tracker(
    printing_selector: case pm1.printing_selector, pm2.printing_selector {
      Some(s1), Some(s2) -> Some(tracking.or_selectors(s1, s2))
      _, _ -> option.or(pm1.printing_selector, pm2.printing_selector)
    },
    change_selector: case pm1.change_selector, pm2.change_selector {
      Some(s1), Some(s2) -> Some(tracking.or_selectors(s1, s2))
      _, _ -> option.or(pm1.change_selector, pm2.change_selector)
    },
    step_specs: list.append(pm1.step_specs, pm2.step_specs),
    interactive_mode: { pm1.interactive_mode || pm2.interactive_mode },
    output: case pm2.output {
      Some(_) -> pm2.output
      None -> pm1.output
    },
    include_selection_ellipses: case pm2.include_selection_ellipses {
      Some(_) -> pm2.include_selection_ellipses
      None -> pm1.include_selection_ellipses
    },
  )
}

fn join_tracking_monitor_factory(
  existing: Option(MonitorFactory),
  tracker: Tracker,
) -> MonitorFactory {
  case existing {
    Some(TrackingMonitorFactory(existing_tracker)) ->
      TrackingMonitorFactory(join_trackers(Some(existing_tracker), tracker))
    _ -> TrackingMonitorFactory(tracker)
  }
}

fn parse_dump_args(
  values: List(String),
) -> Result(#(List(PipelineStepSpec), VxmlMonitorOutput), CommandLineError) {
  use #(output, values) <- on.ok(parse_vxml_monitor_output_arguments(values))
  use specs <- on.ok(parse_pipeline_step_specs(values))
  Ok(#(specs, output))
}

// --times parsing

fn parse_times_args(
  values: List(String),
) -> Result(Option(Int), CommandLineError) {
  case values {
    [] -> Ok(None)
    [x] -> {
      use x <- on.error_ok(int.parse(x), fn(_) {
        Error(TimesValues(
          "could not parse --times argument '" <> x <> "' as integer",
        ))
      })
      let x = int.max(x, 1)
      Ok(Some(x))
    }
    _ -> Error(UnexpectedArgumentsToOption("--times"))
  }
}

// ************************************************************
// RendererParameters + CommandLineAmendments -> RendererParameters
// ************************************************************

pub fn amend_renderer_parameters_by_command_line_amendments(
  parameters: RendererParameters,
  amendments: CommandLineAmendments,
) -> RendererParameters {
  RendererParameters(
    input_dir: option.unwrap(amendments.input_dir, parameters.input_dir),
    output_dir: option.unwrap(amendments.output_dir, parameters.output_dir),
    prettifier_behavior: option.unwrap(
      amendments.prettier,
      parameters.prettifier_behavior,
    ),
  )
}

// ************************************************************
// RendererOptions + CommandLineAmendments -> RendererOptions
// ************************************************************

fn exists_match(
  z: Option(List(a)),
  // List(a) = list of things that might cause a match, left empty if we always want a match
  e: fn(a) -> Bool,
  // match tester
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

fn append_optional_monitor_factory(
  factories: List(MonitorFactory),
  factory: Option(MonitorFactory),
) -> List(MonitorFactory) {
  case factory {
    None -> factories
    Some(factory) -> list.append(factories, [factory])
  }
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
      options.interactive_mode || amendments.tracker_interactive_mode
    },
    warnings: option.unwrap(amendments.warnings, options.warnings),
    only_paths: list.append(options.only_paths, amendments.only_paths),
    only_key_vals: list.append(options.only_key_vals, amendments.only_key_vals),
    only_path_key_vals: list.append(
      options.only_path_key_vals,
      amendments.only_path_key_vals,
    ),
    monitors: options.monitors,
    monitor_factories: options.monitor_factories
      |> append_optional_monitor_factory(amendments.tracking_monitor_factory)
      |> append_optional_monitor_factory(amendments.dump_monitor_factory),
    output_lines_table_default_comment_columns: options.output_lines_table_default_comment_columns,
    output_lines_table_default_blame_columns: options.output_lines_table_default_blame_columns,
    echo_assembled_lines: amendments.echo_assembled
      || options.echo_assembled_lines,
    echo_parsed_vxml: amendments.echo_parsed || options.echo_parsed_vxml,
    echo_filtered_vxml: amendments.echo_filtered || options.echo_filtered_vxml,
    echo_vxml_fragments: fn(fr: OutputFragment(z, VXML)) {
      options.echo_vxml_fragments(fr)
      || exists_match(
        amendments.vxml_fragments_local_paths_to_echo,
        string.contains(fr.path, _),
      )
    },
    echo_output_lines_fragments: fn(fr: OutputFragment(z, List(OutputLine))) {
      options.echo_output_lines_fragments(fr)
      || exists_match(
        amendments.output_lines_fragments_local_paths_to_echo,
        string.contains(fr.path, _),
      )
    },
    echo_string_fragments: fn(fr: OutputFragment(z, String)) {
      options.echo_string_fragments(fr)
      || exists_match(
        amendments.string_fragments_local_paths_to_echo,
        string.contains(fr.path, _),
      )
    },
    echo_prettified_fragments: fn(fr: GhostOfOutputFragment(z)) {
      options.echo_prettified_fragments(fr)
      || exists_match(
        amendments.prettified_fragments_local_paths_to_echo,
        string.contains(fr.path, _),
      )
    },
  )
}

fn resolve_absolute_step(step: Int, pipeline: Pipeline) -> Int {
  let num_steps = list.length(pipeline)
  case step < 0 {
    True -> num_steps + step + 1
    False -> step
  }
}

// ************************************************************
// Pipeline + Tracker -> Pipeline (used by above)
// ************************************************************

fn list_int_cleaner(ze_list: List(Int)) -> List(Int) {
  ze_list |> list.unique |> list.sort(int.compare)
}

type ResolvedStepSelection {
  ResolvedStepSelection(on_change: List(Int), forced: List(Int))
}

fn resolve_absolute_step_range(
  range: AbsoluteStepRange,
  pipeline: Pipeline,
) -> List(Int) {
  let num_steps = list.length(pipeline)
  let #(first, last) = case range {
    ClosedAbsoluteStepRange(first, last) -> #(
      resolve_absolute_step(first, pipeline),
      resolve_absolute_step(last, pipeline),
    )
    AbsoluteStepsFrom(first) -> #(
      resolve_absolute_step(first, pipeline),
      num_steps,
    )
  }
  lo_hi_ints(int.min(first, last), int.max(first, last))
  |> list.filter(fn(step) { step >= 0 && step <= num_steps })
}

fn resolve_desugarer_relative_step_range(
  range: DesugarerRelativeStepRange,
  pipeline: Pipeline,
) -> Result(List(Int), String) {
  let DesugarerRelativeStepRange(name, first_offset, last_offset) = range
  let indices =
    list.index_fold(pipeline, [], fn(acc, desugarer, i) {
      case desugarer.name == name {
        True -> [i, ..acc]
        False -> acc
      }
    })
  use _ <- on.stay(case indices {
    [] -> on.Return(Error("desugarer name not found: " <> name))
    _ -> on.Stay(Nil)
  })
  let num_steps = list.length(pipeline)
  let relative_range = lo_hi_ints(first_offset, last_offset)
  let final_range =
    list.fold(indices, [], fn(acc, index) {
      let step_no = index + 1
      list.fold(relative_range, acc, fn(sub_acc, x) { [step_no + x, ..sub_acc] })
    })
  final_range
  |> list.filter(fn(step) { step >= 0 && step <= num_steps })
  |> list_int_cleaner
  |> Ok
}

fn resolve_pipeline_step_specs(
  specs: List(PipelineStepSpec),
  pipeline: Pipeline,
) -> Result(ResolvedStepSelection, String) {
  use #(on_change, forced) <- on.ok(
    list.try_fold(specs, #([], []), fn(acc, spec) {
      let PipelineStepSpec(range, mode) = spec
      use steps <- on.ok(case range {
        AbsoluteSteps(range) -> Ok(resolve_absolute_step_range(range, pipeline))
        DesugarerRelativeSteps(range) ->
          resolve_desugarer_relative_step_range(range, pipeline)
      })
      case mode {
        OnChange -> Ok(#(list.append(acc.0, steps), acc.1))
        Forced -> Ok(#(acc.0, list.append(acc.1, steps)))
      }
    }),
  )
  let forced = list_int_cleaner(forced)
  let on_change =
    on_change
    |> list_int_cleaner
    |> list.filter(fn(step) { !list.contains(forced, step) })
  Ok(ResolvedStepSelection(on_change, forced))
}

fn monitor_output_heading(context: PipelineStepContext) -> List(String) {
  case context.previous_desugarer {
    None -> ["0. initial pipeline state"]
    Some(desugarer) ->
      pr.name_and_param_string_lines(desugarer, context.step_no, 0)
  }
}

fn selected_vxml(vxml: VXML, selector: Selector) {
  vxml
  |> tracking.vxml_to_s_lines
  |> selector
}

fn selected_output_lines(
  vxml: VXML,
  selector: Selector,
  output: VxmlMonitorOutput,
  include_ellipses: Bool,
  table_indent: Int,
  default_blame_columns: Int,
  default_comment_columns: Int,
) -> List(String) {
  let lines = selected_vxml(vxml, selector)
  case output {
    TrackingVerbatim ->
      tracking.s_lines_verbatim_lines_with_options(
        lines,
        False,
        include_ellipses,
      )
    TrackingTable(blame_columns, comment_columns) -> {
      let blame_columns = option.unwrap(blame_columns, default_blame_columns)
      let comment_columns =
        option.unwrap(comment_columns, default_comment_columns)
      tracking.s_lines_table_lines_with_options(
        lines,
        "",
        False,
        table_indent,
        bl.BlameTableMarginColumnsMinMax(blame_columns, blame_columns),
        bl.BlameTableMarginColumnsMinMax(comment_columns, comment_columns),
        include_ellipses,
      )
    }
  }
}

fn selected_comparison_string(vxml: VXML, selector: Selector) -> String {
  selected_vxml(vxml, selector)
  |> tracking.s_lines_table("", True, 0)
}

fn vxml_monitor_output_margin(
  output: VxmlMonitorOutput,
) -> MonitorOutputMargin {
  case output {
    TrackingTable(_, _) -> AtRunnerMargin
    TrackingVerbatim -> Verbatim
  }
}

fn tracking_monitor_output(
  vxml: VXML,
  selector: Selector,
  context: PipelineStepContext,
  output: VxmlMonitorOutput,
  include_ellipses: Bool,
  default_blame_columns: Int,
  default_comment_columns: Int,
) -> MonitorOutput {
  MonitorOutput(
    lines: [
      "💠",
      ..list.append(monitor_output_heading(context), [
        "💠",
        ..selected_output_lines(
          vxml,
          selector,
          output,
          include_ellipses,
          0,
          default_blame_columns,
          default_comment_columns,
        )
      ])
    ],
    margin: vxml_monitor_output_margin(output),
  )
}

fn make_tracking_monitor(
  tracker: Tracker,
  pipeline: Pipeline,
  default_blame_columns: Int,
  default_comment_columns: Int,
) -> Result(Monitor, String) {
  use ResolvedStepSelection(on_change_steps, forced_steps) <- on.ok(
    resolve_pipeline_step_specs(tracker.step_specs, pipeline),
  )
  let track_all = on_change_steps == [] && forced_steps == []
  let printing_selector =
    option.unwrap(tracker.printing_selector, fn(lines) { lines })
  let change_selector =
    option.unwrap(tracker.change_selector, printing_selector)
  let output = option.unwrap(tracker.output, TrackingTable(None, None))
  let output_margin = vxml_monitor_output_margin(output)
  let include_selection_ellipses =
    option.unwrap(tracker.include_selection_ellipses, True)
  new_monitor("track", #(None, None), fn(vxml, state, context) {
    let #(previous, last_output_step) = state
    let forced = list.contains(forced_steps, context.step_no)
    let on_change = track_all || list.contains(on_change_steps, context.step_no)
    let #(previous, outputs) = case forced || on_change {
      False -> #(previous, [])
      True -> {
        let comparison = selected_comparison_string(vxml, change_selector)
        let monitor_output =
          tracking_monitor_output(
            vxml,
            printing_selector,
            context,
            output,
            include_selection_ellipses,
            default_blame_columns,
            default_comment_columns,
          )
        case forced || Some(comparison) != previous {
          True -> #(Some(comparison), [monitor_output])
          False -> #(Some(comparison), [])
        }
      }
    }
    let outputs = case outputs, context.previous_desugarer {
      [], Some(desugarer)
        if context.step_no > 0
        && context.step_no % tracking_progress_interval == 0
      -> {
        let enough_steps_since_last_output = case last_output_step {
          None -> True
          Some(step_no) ->
            context.step_no - step_no >= tracking_progress_quiet_steps
        }
        case enough_steps_since_last_output {
          True -> [
            MonitorOutput(
              lines: ["..." <> ins(context.step_no) <> ". " <> desugarer.name],
              margin: output_margin,
            ),
          ]
          False -> []
        }
      }
      _, _ -> outputs
    }
    let last_output_step = case outputs {
      [] -> last_output_step
      _ -> Some(context.step_no)
    }
    Ok(#(#(previous, last_output_step), outputs))
  })
  |> Ok
}

fn make_dump_monitor(
  specs: List(PipelineStepSpec),
  output: VxmlMonitorOutput,
  pipeline: Pipeline,
  default_blame_columns: Int,
  default_comment_columns: Int,
) -> Result(Monitor, String) {
  use ResolvedStepSelection(on_change_steps, forced_steps) <- on.ok(
    resolve_pipeline_step_specs(specs, pipeline),
  )
  let selected_steps =
    list.append(on_change_steps, forced_steps) |> list_int_cleaner
  let dump_all = specs == []
  new_monitor("dump", Nil, fn(vxml, state, context) {
    case dump_all || list.contains(selected_steps, context.step_no) {
      False -> Ok(#(state, []))
      True -> {
        let monitor_output =
          MonitorOutput(
            lines: [
              "💠",
              ..list.append(monitor_output_heading(context), [
                "💠",
                ..selected_output_lines(
                  vxml,
                  sl.all(),
                  output,
                  True,
                  0,
                  default_blame_columns,
                  default_comment_columns,
                )
              ])
            ],
            margin: vxml_monitor_output_margin(output),
          )
        Ok(#(state, [monitor_output]))
      }
    }
  })
  |> Ok
}

fn make_monitors(
  options: RendererOptions(z),
  pipeline: Pipeline,
) -> Result(List(Monitor), RendererError(a, b, c, d, e, f)) {
  use built <- on.error_ok(
    list.try_map(options.monitor_factories, fn(factory) {
      case factory {
        TrackingMonitorFactory(tracker) ->
          make_tracking_monitor(
            tracker,
            pipeline,
            options.output_lines_table_default_blame_columns,
            options.output_lines_table_default_comment_columns,
          )
        DumpMonitorFactory(specs, output) ->
          make_dump_monitor(
            specs,
            output,
            pipeline,
            options.output_lines_table_default_blame_columns,
            options.output_lines_table_default_comment_columns,
          )
      }
    }),
    fn(message) { Error(DesugarerNameNotFoundError(message)) },
  )
  Ok(list.append(options.monitors, built))
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

pub type MonitorFailure {
  MonitorFailure(monitor_name: String, step_no: Int, message: String)
}

pub type PipelineExecutionError {
  PipelineDesugaringError(InSituDesugaringError)
  PipelineMonitorError(MonitorFailure)
}

type PipelineProducerState {
  PipelineProducerState(
    vxml: VXML,
    warnings: List(InSituDesugaringWarning),
    durations: List(Duration),
    monitors: List(Monitor),
  )
}

type Message {
  MonitorProducedOutput(MonitorOutput, Int)
  ProducerFinished(
    Result(
      #(VXML, List(InSituDesugaringWarning), List(Duration)),
      PipelineExecutionError,
    ),
  )
}

fn update_monitors(
  main_process_subject: Subject(Message),
  monitors: List(Monitor),
  vxml: VXML,
  context: PipelineStepContext,
) -> Result(List(Monitor), MonitorFailure) {
  monitors
  |> list.try_fold([], fn(next_monitors, monitor) {
    use update <- on.error_ok(monitor.update(vxml, context), fn(message) {
      Error(MonitorFailure(
        monitor_name: monitor.name,
        step_no: context.step_no,
        message: message,
      ))
    })
    let MonitorUpdate(next, outputs) = update
    list.each(outputs, fn(output) {
      send(main_process_subject, MonitorProducedOutput(output, context.step_no))
    })
    Ok([next, ..next_monitors])
  })
  |> result.map(list.reverse)
}

fn producer(
  main_process_subject: Subject(Message),
  vxml: VXML,
  pipeline: Pipeline,
  monitors: List(Monitor),
) -> Nil {
  let first_desugarer = case list.first(pipeline) {
    Ok(desugarer) -> Some(desugarer)
    Error(_) -> None
  }
  let initial_context =
    PipelineStepContext(
      step_no: 0,
      previous_desugarer: None,
      next_desugarer: first_desugarer,
    )
  let final = case
    update_monitors(main_process_subject, monitors, vxml, initial_context)
  {
    Error(failure) -> Error(PipelineMonitorError(failure))
    Ok(monitors) ->
      pipeline
      |> list.index_map(fn(desugarer, index) { #(desugarer, index) })
      |> list.try_fold(
        PipelineProducerState(vxml, [], [], monitors),
        fn(state, indexed_desugarer) {
          let #(desugarer, index) = indexed_desugarer
          let step_no = index + 1
          let now = timestamp.system_time()
          use #(vxml, new_warnings) <- on.error_ok(
            desugarer.transform(state.vxml),
            fn(error) {
              InSituDesugaringError(
                desugarer: desugarer,
                step_no: step_no,
                blame: error.blame,
                message: error.message,
              )
              |> PipelineDesugaringError
              |> Error
            },
          )
          let then = timestamp.system_time()
          let durations = [timestamp.difference(now, then), ..state.durations]
          let new_warnings =
            list.map(new_warnings, fn(warning) {
              InSituDesugaringWarning(
                desugarer: desugarer,
                step_no: step_no,
                blame: warning.blame,
                message: warning.message,
              )
            })
          let next_desugarer = case list.first(list.drop(pipeline, step_no)) {
            Ok(desugarer) -> Some(desugarer)
            Error(_) -> None
          }
          let context =
            PipelineStepContext(
              step_no: step_no,
              previous_desugarer: Some(desugarer),
              next_desugarer: next_desugarer,
            )
          use monitors <- on.error_ok(
            update_monitors(main_process_subject, state.monitors, vxml, context),
            fn(failure) { Error(PipelineMonitorError(failure)) },
          )
          Ok(PipelineProducerState(
            vxml: vxml,
            warnings: list.append(state.warnings, new_warnings),
            durations: durations,
            monitors: monitors,
          ))
        },
      )
      |> result.map(fn(state) { #(state.vxml, state.warnings, state.durations) })
  }

  send(main_process_subject, ProducerFinished(final))
}

fn print_monitor_output(output: MonitorOutput, runner_margin: Int) -> Nil {
  let MonitorOutput(lines, margin) = output
  let margin = case margin {
    AtRunnerMargin -> string.repeat(" ", runner_margin)
    Verbatim -> ""
  }
  lines
  |> list.map(fn(line) { margin <> line })
  |> string.join("\n")
  |> io.println
}

fn loop(
  subject: Subject(Message),
  countdown: Int,
  // pause for user only when countdown == 0
) -> Result(
  #(VXML, List(InSituDesugaringWarning), List(Duration)),
  Result(UserExit, PipelineExecutionError),
) {
  case receive(subject, within: 100_000) {
    Ok(MonitorProducedOutput(output, step_no)) -> {
      print_monitor_output(output, pipeline_runner_margin)
      case countdown == 0 {
        False -> {
          loop(subject, countdown - 1)
        }
        True ->
          case input.input("(↵|<n>|e|c) ") {
            Ok(msg) -> {
              let #(countdown, quit) = case int.parse(msg) {
                Ok(q) -> #(q, False)
                Error(_) ->
                  case msg {
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
        Ok(value) -> Ok(value)
        Error(error) -> Error(Error(error))
      }
    }

    Error(_) -> {
      io.println("Timeout while waiting for messages. Is the producer stuck?")
      panic
    }
  }
}

pub fn run_pipeline(
  vxml: VXML,
  pipeline: Pipeline,
  monitors: List(Monitor),
  interactive_mode: Bool,
) -> Result(
  #(VXML, List(InSituDesugaringWarning), List(Duration)),
  Result(UserExit, PipelineExecutionError),
) {
  let main_subject = process.new_subject()

  let producer_pid =
    spawn(fn() { producer(main_subject, vxml, pipeline, monitors) })

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

fn sanitize_input_output_dirs(
  parameters: RendererParameters,
) -> RendererParameters {
  RendererParameters(
    ..parameters,
    input_dir: core.drop_ending_slash(parameters.input_dir),
    output_dir: core.drop_ending_slash(parameters.output_dir),
  )
}

fn echo_vxml(vxml: VXML, banner: String, indent: Int) -> Nil {
  case vp.vxml_to_output_lines(vxml) {
    Ok(lines) -> lines |> io_l.output_lines_table(banner, indent) |> io.println
    Error(error) -> {
      error.partial |> io_l.output_lines_table(banner, indent) |> io.println
      io.println("VXML serialization error: " <> ins(error))
    }
  }
}

fn create_dirs_on_path_to_file(
  path_to_file: String,
) -> Result(Nil, simplifile.FileError) {
  let pieces = path_to_file |> string.split("/")
  let pieces = core.drop_last(pieces)
  list.try_fold(pieces, ".", fn(acc, piece) {
    let acc = acc <> "/" <> piece
    use exists <- on.ok(simplifile.is_directory(acc))
    use _ <- on.ok(case exists {
      True -> Ok(Nil)
      False -> simplifile.create_directory(acc)
    })
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
  MonitorError(MonitorFailure)
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

  let input_dir = parameters.input_dir
  let output_dir = parameters.output_dir
  let prettifier_mode = parameters.prettifier_behavior

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
      let spaces = string.repeat(" ", string.length("  -> assembled "))

      list.index_map(tree |> dt.pretty_print(1), fn(line, i) {
        case i == 0 {
          True -> "  -> assembled "
          False -> spaces
        }
        <> line
      })
      |> string.join("\n")
      |> io.println
    }
    _, _ -> Nil
  }

  case options.echo_assembled_lines {
    False -> Nil
    True -> {
      assembled
      |> io_l.input_lines_table("", 2)
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
    True -> echo_vxml(parsed, "parsed:", 2)
  }

  use filtered <- on.error_ok(renderer.filterer(parsed), fn(c) {
    io.println("  ...filtration error:")
    io.println("")
    [
      #("", ins(c) |> pr.strip_quotes),
    ]
    |> pr.two_column_error_announcer(0, 70, "💥", 2, "/ filtration error /")
    |> io.println
    Error(FiltrationError(c))
  })

  case options.echo_filtered_vxml {
    False -> Nil
    True -> echo_vxml(filtered, "filtered:", 2)
  }

  // 🌸 pipeline 🌸

  io.println("• starting pipeline...")
  let t0 = timestamp.system_time()

  use monitors <- on.error_ok(
    make_monitors(options, renderer.pipeline),
    on_error: fn(error) {
      io.println("  ...error:")
      io.println("")
      [#("", ins(error))]
      |> pr.two_column_error_announcer(
        0,
        70,
        "💥",
        2,
        "/ monitor option error /",
      )
      |> io.println
      Error(error)
    },
  )

  use #(desugared, warnings, durations) <- on.error_ok(
    run_pipeline(
      filtered,
      renderer.pipeline,
      monitors,
      options.interactive_mode,
    ),
    on_error: fn(e) {
      case e {
        Ok(UserExit(step_no)) -> {
          io.println("")
          io.println("user exit at step_no " <> ins(step_no))
          Error(UserExitError(step_no))
        }
        Error(PipelineDesugaringError(e)) -> {
          io.println("  ...desugaring error:")
          io.println("")
          [
            #(" desugarer:  ", e.desugarer.name <> ".gleam"),
            #(" step: ", ins(e.step_no)),
            #(" blame:", pr.our_blame_digest(e.blame)),
            #(" message:", e.message),
          ]
          |> pr.mushroom_error_announcement("DesugaringError", _)
          |> io.println
          Error(PipelineError(e))
        }
        Error(PipelineMonitorError(failure)) -> {
          let MonitorFailure(name, step_no, message) = failure
          io.println("  ...pipeline stopped by monitor:")
          io.println("")
          [
            #(" step:", ins(step_no)),
            #(" message:", message),
          ]
          |> pr.mushroom_error_announcement("'" <> name <> "' monitor error", _)
          |> io.println
          Error(MonitorError(failure))
        }
      }
    },
  )

  let t1 = timestamp.system_time()
  let seconds =
    timestamp.difference(t0, t1) |> duration.to_seconds |> float.to_precision(3)

  case options.profiling_table {
    None -> {
      io.println("  ..ended pipeline (" <> ins(seconds) <> "s)")
    }

    Some(total_chars) -> {
      let all_seconds =
        durations |> list.map(duration.to_seconds) |> list.reverse
      let assert Ok(max_secs) = list.max(all_seconds, float.compare)
      let num_hundreth_seconds = float.ceiling(max_secs *. 100.0)
      let one_hundreth_seconds_num_bars =
        int.to_float(total_chars) /. num_hundreth_seconds
      let scale =
        list.repeat(Nil, float.round(num_hundreth_seconds) + 1)
        |> list.map_fold(0.0, fn(x, _) { #(x +. 0.01, x) })
        |> pair.second
        |> list.index_fold("", fn(acc, seconds, i) {
          let start_char =
            float.round(int.to_float(i) *. one_hundreth_seconds_num_bars)
          let num_spaces = start_char - string.length(acc)
          case num_spaces > 0 || acc == "" {
            False -> acc
            True -> {
              let label = ins(seconds |> float.to_precision(2)) <> "s"
              acc <> string.repeat(" ", num_spaces) <> label
            }
          }
        })
      assert list.length(all_seconds) == list.length(renderer.pipeline)
      let bars =
        list.index_map(list.zip(renderer.pipeline, all_seconds), fn(pair, i) {
          let #(desugarer, seconds) = pair
          case desugarer.name {
            "table_marker" -> [" ", "% table_marker %", " "] |> list.map(Or)
            "table_section_header" -> {
              let assert Some(header) = desugarer.stringified_param
              ["/", "/ " <> header <> " /", "/"] |> list.map(Or)
            }
            _ -> {
              let num_bars =
                float.round(seconds *. 100.0 *. one_hundreth_seconds_num_bars)
              [
                Either(#(ins(i + 1) <> ".", desugarer.name, pr.blocks(num_bars))),
              ]
            }
          }
        })
        |> list.flatten
      pr.three_column_table([Either(#("#.", "name", scale)), ..bars])
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
      |> pr.mushroom_error_announcement("splitter error", _)
      |> io.println
      Error(SplitterError(error))
    },
  )

  let prefix = "[" <> output_dir <> "/]"
  let fragments_types_and_paths_4_table =
    list.map(fragments, fn(fr) { #(ins(fr.classifier), prefix <> fr.path) })

  case options.verbose {
    False -> {
      io.println(
        "  -> obtained "
        <> pr.how_many("fragment", "fragments", list.length(fragments)),
      )
    }
    True -> {
      io.println(
        "  -> obtained "
        <> pr.how_many("fragment", "fragments", list.length(fragments))
        <> ":",
      )
      [#("classifier", "path"), ..fragments_types_and_paths_4_table]
      |> pr.two_column_table
      |> pr.print_lines_at_indent(2)
    }
  }

  fragments
  |> list.each(fn(fr) {
    case options.echo_vxml_fragments(fr) {
      False -> Nil
      True -> echo_vxml(fr.payload, "fr:" <> fr.path, 2)
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

  let num_emitter_errors =
    list.fold(fragments, 0, fn(acc, fr) {
      case fr {
        Ok(_) -> acc
        _ -> acc + 1
      }
    })

  list.each(fragments, fn(fr) {
    use error <- on.ok_error(fr, fn(_) { Nil })
    io.println("  emitter error:")
    io.println("")
    [
      #("", ins(error)),
    ]
    |> pr.mushroom_error_announcement("emitter error", _)
    |> io.println
  })

  case num_emitter_errors {
    0 -> Nil
    _ -> io.println("")
  }

  io.println("• converting List(OutputLine) fragments to String fragments...")

  let fragments = {
    fragments
    |> list.map(
      on.error_ok(_, fn(error) { Error(P1(error)) }, fn(fr) {
        Ok(
          OutputFragment(..fr, payload: io_l.output_lines_to_string(fr.payload)),
        )
      }),
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
            let header =
              "────────────────── writer echo: "
              <> fr.path
              <> " ──────────────────"
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
    |> list.map_fold(0, fn(acc, result) {
      use fr <- on.error_ok(result, fn(e) { #(acc, Error(e)) })
      case renderer.writer(output_dir, fr) {
        Error(e) -> #(acc, Error(P2(e)))
        Ok(z) -> {
          case singleton_fragment {
            True -> io.println("  -> wrote [" <> output_dir <> "/]" <> fr.path)
            False ->
              case options.verbose || options.artifacts {
                True -> io.println("  wrote [" <> output_dir <> "/]" <> fr.path)
                False -> Nil
              }
          }
          #(acc + 1, Ok(z))
        }
      }
    })

  case options.verbose || options.artifacts {
    False ->
      case count {
        1 ->
          case singleton_fragment {
            True -> Nil
            // we already announced (see above)
            False ->
              io.println(
                "  -> wrote 1 file (use '--artifacts' or '--verbose' to see)",
              )
          }
        _ ->
          io.println(
            "  -> wrote "
            <> ins(count)
            <> " files (use '--artifacts' or '--verbose' to see)",
          )
      }
    True -> Nil
  }

  // 🌸 prettifying 🌸

  let run_prettification = fn(result, dest_dir) {
    use fr: GhostOfOutputFragment(z) <- on.eager_error_ok(result, Nil)
    case dest_dir {
      None ->
        io.print(
          "  prettify-checking [" <> output_dir <> "]" <> fr.path <> "...",
        )
      Some(dir) ->
        io.print(
          "  prettifying ["
          <> output_dir
          <> "/]"
          <> fr.path
          <> " -> ["
          <> dir
          <> "/]"
          <> fr.path
          <> "...",
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
          " "
          <> ins(x)
          <> " warnings"
          <> warn_suffix
          <> " "
          <> ins(y)
          <> " errors"
          <> end,
        )
        case options.warnings {
          True ->
            list.each(warns, fn(w) {
              io.println("  👾👾--- warning ---👾👾: " <> w)
            })
          False -> Nil
        }
        list.each(errs, fn(e) { io.println("  🍄🍄--- error ---🍄🍄: " <> e) })
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
        use file_contents <- on.error_ok(simplifile.read(path), fn(error) {
          io.println("")
          io.println(
            "could not read back printed file " <> path <> ":" <> ins(error),
          )
        })
        io.println("")
        let header =
          "───────────── prettifier echo: " <> fr.path <> " ──────────────────"
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
          io.println(
            "\n👉 "
            <> pr.how_many("warning", "warnings", list.length(warnings))
            <> ":",
          )
        False ->
          io.println(
            "\n["
            <> pr.how_many(
              "suppressed warning",
              "suppressed warnings",
              list.length(warnings),
            )
            <> " (use '--warnings' option to see)]",
          )
      }
    }
  }

  case options.warnings {
    True ->
      list.each(warnings, fn(w) {
        io.println("")
        [
          #(" from:", w.desugarer.name <> " (desugarer)"),
          #(" pipeline step: ", ins(w.step_no)),
          #(" blame:", bl.blame_digest(w.blame)),
          #(" message:", w.message),
        ]
        |> pr.two_column_error_announcer(0, 60, "👾", 2, "")
        |> io.println
      })
    False -> Nil
  }

  let #(oks, errors) = result.partition(fragments)

  case errors {
    [] -> Ok(oks |> list.map(fn(ghost) { ghost.path }))
    _ -> Error(EmittingOrWritingErrors(errors))
  }
}
