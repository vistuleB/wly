import argv
import gleam/io
import gleam/string.{inspect as ins}

pub fn main() {
  io.println(argv.load().arguments |> ins)
}
