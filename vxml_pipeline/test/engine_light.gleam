import argv
import gleam/io
import gleam/string.{inspect as ins}
import infrastructure as infra
import vxml_renderer as vr
import desugarer_library as dl
import selector_library as sl
import on

fn pipeline() -> infra.Pipeline {
  [
    dl.identity(),
    dl.rearrange_links(#("Theorem <a href=1>_1_</a>", "<a href=1>Theorem _1_</a>")),
  ]
  |> infra.desugarers_2_pipeline(
    sl.all(),
    infra.TrackingOff,
  )
}

pub fn main() {
  use amendments <- on.error_ok(
    vr.process_command_line_arguments(argv.load().arguments, []),
    fn(e) {
      io.println("")
      io.println("cli error: " <> ins(e))
      vr.basic_cli_usage()
    },
  )

  use <- on.lazy_true_false(
    amendments.help,
    fn() { io.println("test_renderer exiting on '--help' option") },
  )

  let renderer =
    vr.Renderer(
      assembler: vr.default_assembler(amendments.only_paths),
      parser: vr.default_writerly_parser(amendments.only_key_values),
      pipeline: pipeline(),
      splitter: vr.stub_splitter(".tsx"),
      emitter: vr.stub_jsx_emitter,
      prettifier: vr.default_prettier_prettifier,
    )
    |> vr.amend_renderer_by_command_line_amendments(amendments)

  let parameters =
    vr.RendererParameters(
      table: True,
      input_dir: "samples/sample.wly",
      output_dir: "samples/output",
      prettifier_behavior: vr.PrettifierOff,
    )
    |> vr.amend_renderer_paramaters_by_command_line_amendments(amendments)


  let debug_options =
    vr.default_renderer_debug_options()
    |> vr.amend_renderer_debug_options_by_command_line_amendments(amendments)

  let _ = vr.run_renderer(renderer, parameters, debug_options)

  Nil
}
