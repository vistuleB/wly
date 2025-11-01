import gleam/io
import gleam/string.{inspect as ins}
import gleam/list
import gleam/result
import simplifile
import vxml
import writerly as wl
import on

fn contents_test() -> Result(Nil, String) {
  io.println("\n### CONTENTS_TEST ###")

  let dirname = "samples/contents"

  use #(tree, lines) <- on.error_ok(
    wl.assemble_input_lines(dirname),
    fn(e) { Error("CONTENTS_TEST ERROR: AssemblyError: " <> ins(e)) }
  )

  io.println("\nassembled:\n")
  tree |> list.map(fn(x) { "" <> x }) |> string.join("\n") |> io.println()
  io.println("")

  use writerlys <- on.error_ok(
    wl.parse_input_lines(lines),
    fn(e) { Error("CONTENTS_TEST ERROR: " <> ins(e)) },
  )

  let vxmls =
    writerlys
    |> list.map(wl.writerly_to_vxml)

  list.index_map(
    writerlys,
    fn (writerly, i) {
      wl.writerly_table(writerly, "#" <> ins(i + 1), 0) |> io.println
    }
  )

  list.index_map(
    vxmls,
    fn (vxml, i) {
      vxml.vxml_table(vxml, "#" <> ins(i + 1), 0) |> io.println
    }
  )

  io.println("[end]")

  Ok(Nil)
}

fn sample_test() -> Result(Nil, String) {
  io.println("\n### SAMPLE_TEST ###")

  let filename = "samples/sample.wly"

  use contents <- on.error_ok(
    simplifile.read(filename),
    fn(_) { Error("SAMPLE_TEST error: i/o error while reading " <> filename) }
  )

  use writerlys <- on.error_ok(
    wl.parse_string(contents, filename),
    fn(e) { Error("SAMPLE_TEST error: parsing error: " <> ins(e)) },
  )

  io.println("")
  io.println("list.length(writerlys) == " <> ins(list.length(writerlys)))
  io.println("")

  writerlys
  |> list.index_map(
    fn (writerly, i) {
      wl.writerly_table(writerly, "sample_test writerly " <> ins(i + 1), 0) |> io.println
    }
  )

  let vxmls = writerlys |> list.map(wl.writerly_to_vxml)

  io.println("list.length(vxmls) == " <> ins(list.length(vxmls)))
  io.println("")

  vxmls
  |> list.index_map(
    fn (wxml, i) {
      vxml.vxml_table(wxml, "sample_test vxml" <> ins(i + 1), 0) |> io.println
    }
  )

  let writerlys = list.map(vxmls, wl.vxml_to_writerly) |> list.filter(result.is_ok)

  list.each(
    writerlys,
    fn(w) {
      let assert Ok(w) = w
      wl.writerly_table(w, "back to writerly!", 0) |> io.println
    }
  )

  io.println("[end]")

  Ok(Nil)
}

fn html_test() -> Result(Nil, String) {
  io.println("\n### HTML_TEST ###")

  let path = "samples/ch5_ch.xml"

  use content <- on.error_ok(
    simplifile.read(path),
    fn(_) { Error("HTML_TEST ERROR: problem reading " <> path) }
  )

  use vxml <- on.error_ok(
    vxml.xmlm_based_html_parser(content, path),
    fn(e) { Error("HTML_TEST ERROR: xmlm_based_html_parser error: " <> ins(e)) },
  )

  let writerlys = wl.vxml_to_writerlys(vxml)

  io.println("")
  io.println("list.length(writerlys) == " <> ins(list.length(writerlys)))
  io.println("")

  writerlys
  |> list.index_map(
    fn (writerly, i) {
      wl.writerly_table(
        writerly,
        "html_test " <> ins(i + 1),
        0,
      ) |> io.println
    }
  )

  let _ = simplifile.write(
    "samples/ch5_ch.wly",
    writerlys
    |> list.map(wl.writerly_to_string)
    |> string.concat
  )

  io.println("[end]")

  Ok(Nil)
}

pub fn main() {
  let errors = [
    sample_test(),
    // contents_test(),
    // html_test(),
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
