import desugaring/desugarers as dl
import desugaring as ds
import desugaring/core as core

fn smoke_pipeline() -> core.Pipeline {
  [
    dl.identity(),
    dl.rename(#("Chapter", "section")),
    dl.append_attribute(#("section", "class", "smoke-section", core.GoBack)),
  ]
}

pub fn run_renderer_smoke_test() {
  let options = ds.vanilla_options()

  let parameters =
    ds.RendererParameters(
      input_dir: "samples/smoke.xml",
      output_dir: "build/renderer-smoke-output",
      prettifier_behavior: ds.PrettifierOff,
    )

  let renderer =
    ds.Renderer(
      assembler: ds.default_file_assembler,
      filterer: ds.default_filterer(_, options, []),
      parser: ds.default_xml_parser,
      pipeline: smoke_pipeline(),
      splitter: ds.stub_splitter(".tsx"),
      emitter: ds.stub_jsx_emitter,
      writer: ds.default_writer,
      prettifier: ds.default_prettier_prettifier,
    )

  let assert Ok(_) = ds.run_renderer(renderer, parameters, options)

  Nil
}

pub fn main() {
  run_renderer_smoke_test()
}
