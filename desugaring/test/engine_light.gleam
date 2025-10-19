import argv
import gleam/io
import gleam/string.{inspect as ins}
import infrastructure as infra
import desugaring as ds
import desugarer_library as dl
import on

fn pipeline() -> infra.Pipeline {
  [
    dl.identity(),
    dl.rearrange_links(#("Theorem <a href=1>_1_</a>", "<a href=1>Theorem _1_</a>")),
  ]
  |> infra.desugarers_2_pipeline
}

pub fn run_renderer_test() {
  use amendments <- on.error_ok(
    ds.process_command_line_arguments(argv.load().arguments, []),
    fn(e) {
      io.println("")
      io.println("cli error: " <> ins(e))
      ds.basic_cli_usage("")
    },
  )

  use <- on.lazy_true_false(
    amendments.help,
    fn() { io.println("test_renderer exiting on '--help' option") },
  )

  let renderer =
    ds.Renderer(
      assembler: ds.default_assembler(amendments.only_paths),
      parser: ds.default_writerly_parser(amendments.only_key_values),
      pipeline: pipeline(),
      splitter: ds.stub_splitter(".tsx"),
      emitter: ds.stub_jsx_emitter,
      writer: ds.default_writer,
      prettifier: ds.default_prettier_prettifier,
    )
    |> ds.amend_renderer_by_command_line_amendments(amendments)

  let parameters =
    ds.RendererParameters(
      input_dir: "samples/sample.wly",
      output_dir: "samples/output",
      prettifier_behavior: ds.PrettifierOff,
      table: False,
      verbose: False,
      warnings: False,
    )
    |> ds.amend_renderer_paramaters_by_command_line_amendments(amendments)


  let debug_options =
    ds.default_renderer_debug_options()
    |> ds.amend_renderer_debug_options_by_command_line_amendments(amendments)

  let _ = ds.run_renderer(renderer, parameters, debug_options)

  Nil
}

pub fn main() {
  run_renderer_test()
}
