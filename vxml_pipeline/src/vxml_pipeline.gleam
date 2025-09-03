import gleam/list
import argv
import gleam/io
import gleam/string.{inspect as ins}
import infrastructure.{type Pipe} as infra
import vxml_renderer as vr
import desugarer_library as dl
import selector_library as sl
import on

fn test_pipeline() -> List(Pipe) {
  [
    dl.identity(),
    dl.rearrange_links(#("Theorem <a href=1>_1_</a>", "<a href=1>Theorem _1_</a>")),
  ]
  |> infra.desugarers_2_pipeline(
    sl.all(),
    infra.TrackingOff,
  )
}

fn test_renderer() {
  use amendments <- on.error_ok(
    vr.process_command_line_arguments(argv.load().arguments, []),
    fn(e) {
      io.println("")
      io.println("cli error: " <> ins(e))
      vr.basic_cli_usage()
    },
  )

  use <- on.true_false(
    amendments.help,
    io.println("test_renderer exiting on '--help' option"),
  )

  let renderer =
    vr.Renderer(
      assembler: vr.default_assembler(amendments.only_paths),
      parser: vr.default_writerly_parser(amendments.only_key_values),
      pipeline: test_pipeline(),
      splitter: vr.stub_splitter(".tsx"),
      emitter: vr.stub_jsx_emitter,
      prettifier: vr.default_prettier_prettifier,
    )
    |> vr.amend_renderer_by_command_line_amendments(amendments)

  let parameters =
    vr.RendererParameters(
      table: True,
      input_dir: "test/sample.wly",
      output_dir: "test/output",
      prettifier_behavior: vr.PrettifierOff,
    )
    |> vr.amend_renderer_paramaters_by_command_line_amendments(amendments)


  let debug_options =
    vr.default_renderer_debug_options()
    |> vr.amend_renderer_debug_options_by_command_line_amendments(amendments)

  let _ = vr.run_renderer(renderer, parameters, debug_options)

  Nil
}

pub fn test_thing() {
  // let assert Ok([vxml]) = vxml.parse_file("test/sample.vxml")
  // echo vxml
  dl.rearrange_links(#("Theorem <a href=1>_1_</a>", "<a href=1>Theorem _1_</a>"))
  Nil
}

pub fn main() {
  case argv.load().arguments {
    ["--test-thing"] -> {
      test_thing()
    }
    ["--test-desugarers", ..names] -> {
      let collections = list.map(dl.assertive_tests, fn(constructor){constructor()})
      infra.run_assertive_desugarer_tests(names, collections)
    }
    _ -> {
      io.println("")
      io.println("No local command line options given. Will run the test renderer.")
      test_renderer()
    }
  }
}
