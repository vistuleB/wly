import gleam/order
import gleam/option.{type Option, None, Some}
import gleam/list
import gleam/string
import gleam/io

pub type DirTreeV2 {
  Filepath(name: String)
  Dirpath(name: String, contents: List(DirTreeV2))
}

pub fn from_paths_acc(
  previous: List(DirTreeV2),
  under_construction: Option(#(String, List(List(String)))),
  remaining: List(List(String)),
) -> List(DirTreeV2) {
  let package_current = fn(name: String, decomposed_paths) {
    assert name != ""
    let subdirs = from_paths_acc([], None, decomposed_paths |> list.reverse)
    Dirpath(name, subdirs)
  }

  case remaining, under_construction {
    [], None -> previous |> list.reverse

    [], Some(#(name, decomposed_paths)) -> {
      let constructed = package_current(name, decomposed_paths)
      [constructed, ..previous] |> list.reverse
    }

    [first, ..rest], None -> {
      case first {
        [] -> panic

        [""] -> from_paths_acc(previous, None, rest)

        [filename] -> {
          let constructed = Filepath(filename)
          from_paths_acc([constructed, ..previous], None, rest)
        }

        [dirname, ..decomposed_path] -> {
          assert dirname != ""
          from_paths_acc(previous, Some(#(dirname, [decomposed_path])), rest)
        }
      }
    }

    [first, ..rest], Some(#(name, decomposed_paths)) -> {
      case first {
        [] -> panic

        [""] -> panic

        [filename] -> {
          assert filename != name
          let constructed1 = package_current(name, decomposed_paths)
          let constructed2 = Filepath(filename)
          from_paths_acc(
            [constructed2, constructed1, ..previous],
            None,
            rest,
          )
        }

        [dirname, ..decomposed_path] if dirname == name -> {
          from_paths_acc(
            previous,
            Some(#(name, [decomposed_path, ..decomposed_paths])),
            rest,
          )
        }

        [dirname, ..decomposed_path] if dirname != name -> {
          let constructed1 = package_current(name, decomposed_paths)
          from_paths_acc(
            [constructed1, ..previous],
            Some(#(dirname, [decomposed_path])),
            rest,
          )
        }

        _ -> panic
      }
    }
  }
}

pub fn from_paths(
  dirname: String,
  paths: List(String),
) ->  DirTreeV2 {
  let dirname = case string.ends_with(dirname, "/") {
    True -> dirname
    False -> dirname <> "/"
  }

  let dirname_length = dirname |> string.length

  let paths =
    paths
    |> list.map(fn(path) {
      let path = case string.starts_with(path, dirname) {
        True -> string.drop_start(path, dirname_length)
        False -> path
      }
      assert !string.starts_with(path, "/")
      path
    })
    |> list.sort(string.compare)
    |> list.map(string.split(_, "/"))

  let dirname = string.drop_end(dirname, 1)

  Dirpath(dirname, from_paths_acc([], None, paths))
}

pub fn sort(
  tree: DirTreeV2,
  order: fn(DirTreeV2, DirTreeV2) -> order.Order,
) -> DirTreeV2 {
  case tree {
    Filepath(_) -> tree
    Dirpath(name, contents) -> {
      let contents =
        contents
        |> list.map(sort(_, order))
        |> list.sort(order)
      Dirpath(name, contents)
    }
  }
}

pub fn main() {
  let paths = [
    "hello/a",
    "hello/b",
    "hello/c/a",
    "hello/c/b",
    "hello/c/c/a",
    "hello/c/c/b",
    "hello/c/c/c/a",
    "hello/c/c/c/b",
    "bitch",
  ]
  let tree = from_paths(
    "/home/jpsteinb",
    paths,
  )
  pretty_printer(tree)
  |> string.join("\n")
  |> io.println
}

fn directory_pretty_printer_add_margin(
  lines: List(String),
  is_last: Bool,
) -> List(String) {
  let t = "├─ "
  let b = "│  "
  let l = "└─ "
  let s = "   "
  case is_last {
    False -> list.index_map(
      lines,
      fn (line, i) {
        case i == 0 {
          True -> t <> line
          False -> b <> line
        }
      }
    )
    True -> list.index_map(
      lines,
      fn (line, i) {
        case i == 0 {
          True -> l <> line
          False -> s <> line
        }
      }
    )
  }
}

pub fn pretty_printer(tree: DirTreeV2) -> List(String) {
  case tree {
    Filepath(path) -> [path]
    Dirpath(path, children) -> {
      let num_children = children |> list.length
      let xtra_margin = case string.reverse(path) |> string.split_once("/") {
        Ok(#(_, after)) -> string.length(after) + 1
        _ -> 0
      }
      let xtra_margin = string.repeat(" ", xtra_margin)
      list.index_map(
        children,
        fn (child, i) {
          pretty_printer(child)
          |> directory_pretty_printer_add_margin(i == num_children - 1)
          |> list.map(fn(line){xtra_margin <> line})
        }
      )
      |> list.flatten
      |> list.prepend(path)
    }
  }
}
