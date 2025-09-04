import gleam/result
import gleam/io
import gleam/list
import gleam/string.{inspect as ins}
import simplifile
import vxml
import io_lines as io_l
import on

fn html_engine_light() -> Result(Nil, String) {
  io.println("\n### HTML ENGINE LIGHT ###\n")

  let path = "samples/sample.html"

  use content <- on.error_ok(
    simplifile.read(path),
    fn(e) { Error("html_engine_light i/o error wile reading '" <> path <> "'") },
  )

  use vxml <- on.error_ok(
    vxml.xmlm_based_html_parser(content, path),
    fn(e) { Error("html_engine_light xmlm_based_html_parser error: " <> ins(e)) },
  )

  vxml.echo_vxml(vxml, "html_engine_light")

  vxml.vxml_to_html_output_lines(vxml, 0, 2)
  |> io_l.echo_output_lines("back to html")

  io.println("[end]")
  
  Ok(Nil)
}

fn vxml_engine_light() -> Result(Nil, String) {
  io.println("\n### VXML ENGINE LIGHT ###\n")

  let path = "samples/sample.vxml"

  use vxmls <- on.error_ok(
    vxml.parse_file(path),
    fn (e) {
      case e {
        vxml.IOError(error) -> Error("vxml_engine_light i/o error on '" <> path <> "': " <> ins(error))
        vxml.DocumentError(error) -> Error("vxml_engine_light parsing error: " <> ins(error))
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

  io.println("[end]")

  Ok(Nil)
}

pub fn main() {
  let errors = [
    html_engine_light(),
    vxml_engine_light(),
  ] |> list.filter(result.is_error)

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

  list.each(
    errors,
    fn(error) { io.println(ins(error)) }
  )
}