import gleam/io
import gleam/list
import gleam/string.{inspect as ins}
import simplifile
import vxml
import io_lines as io_l
import on

fn html_engine_light() -> Nil {
  let path = "samples/sample.html"

  use content <- on.error_ok(
    simplifile.read(path),
    fn(_) { io.println("could not read file " <> path) },
  )

  use vxml <- on.error_ok(
    vxml.xmlm_based_html_parser(content, path),
    fn(e) { io.println("xmlm_based_html_parser error: " <> ins(e)) },
  )

  vxml.echo_vxml(vxml, "html_engine_light")

  vxml.vxml_to_html_output_lines(vxml, 0, 2)
  |> io_l.echo_output_lines("back to html")

  Nil
}

fn vxml_engine_light() {
  let path = "samples/sample.vxml"

  use vxmls <- on.error_ok(
    vxml.parse_file(path),
    fn (e) {
      case e {
        vxml.IOError(error) -> io.println("there was an IOError: " <> ins(error))
        vxml.DocumentError(error) -> io.println("there was a parsing error: " <> ins(error))
      }
    }
  )

  io.println("list.length(vxmls) == " <> ins(list.length(vxmls)))
  io.println("")

  vxmls
  |> list.index_map(
    fn (vxml, i) {
      vxml.echo_vxml(vxml, "vxml_engine_light " <> ins(i + 1))
      io.println("")
    }
  )

  Nil
}

pub fn main() {
  io.println("\n### HTML ENGINE LIGHT ###\n")
  html_engine_light()
  io.println("\n### VXML ENGINE LIGHT ###\n")
  vxml_engine_light()
}