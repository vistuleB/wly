import gleam/io
import gleam/list
import gleam/result
import gleam/string.{inspect as ins}
import io_lines as io_l
import on
import simplifile
import vxml

fn streaming_parser_engine_light() -> Result(Nil, String) {
  io.println("\n### STREAMING PARSER ENGINE LIGHT ###\n")

  let path = "samples/sample2.html"

  use content <- on.error_ok(simplifile.read(path), fn(_) {
    Error(
      "streaming_parser_engine_light i/o error wile reading '" <> path <> "'",
    )
  })

  use vxml <- on.error_ok(
    content
      |> vxml.html_repair
      |> vxml.parse_xml(path),
    fn(e) {
      let #(_, msg) = e
      io.println("")
      io.println("got error in streaming parser:")
      io.println("- msg:   " <> msg)
      Error("streaming_parser_engine_light")
    },
  )

  vxml.vxml_table(vxml, "streamer success!", 0) |> io.println

  Ok(Nil)
}

fn html_engine_light() -> Result(Nil, String) {
  io.println("\n### HTML ENGINE LIGHT ###\n")

  let path = "samples/sample.html"

  use content <- on.error_ok(simplifile.read(path), fn(_) {
    Error("html_engine_light i/o error wile reading '" <> path <> "'")
  })

  use vxml <- on.error_ok(
    content |> vxml.html_repair |> vxml.parse_xml(path),
    fn(e) { Error("html_engine_light parse_xml error: " <> ins(e)) },
  )

  vxml.vxml_table(vxml, "html_engine_light", 0) |> io.println

  vxml.vxml_to_html_output_lines(vxml, 0, 2)
  |> io_l.output_lines_table("back to html", 0)
  |> io.println

  io.println("[end]")

  Ok(Nil)
}

fn vxml_engine_light() -> Result(Nil, String) {
  io.println("\n### VXML ENGINE LIGHT ###\n")

  let path = "samples/sample.vxml"

  use vxmls <- on.error_ok(vxml.parse_file(path, False), fn(e) {
    case e {
      vxml.IOError(error) ->
        Error("vxml_engine_light i/o error on '" <> path <> "': " <> ins(error))
      vxml.DocumentError(error) ->
        Error("vxml_engine_light parsing error: " <> ins(error))
    }
  })

  io.println("list.length(vxmls) == " <> ins(list.length(vxmls)))
  io.println("")

  vxmls
  |> list.index_map(fn(vxml, i) {
    vxml
    |> vxml.vxml_table("vxml_engine_light " <> ins(i + 1), 0)
    |> io.println
  })

  io.println("[end]")

  Ok(Nil)
}

pub fn make_linter_shut_up() {
  let _ = html_engine_light()
  let _ = vxml_engine_light()
  let _ = streaming_parser_engine_light()
}

pub fn main() {
  let errors =
    [
      html_engine_light(),
      vxml_engine_light(),
      streaming_parser_engine_light(),
    ]
    |> list.filter(result.is_error)

  io.println("\n[end all]\n")

  case errors {
    [] -> Nil
    [_one] -> {
      io.println("1 error:\n")
    }
    _ -> {
      io.println(ins(list.length(errors)) <> " errors:\n")
    }
  }

  list.each(errors, fn(error) { io.println(ins(error)) })
}
