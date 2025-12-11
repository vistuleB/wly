import gleam/option.{type Option, None, Some}
import gleam/list
import gleam/string
import gleam/result
import filepath

pub type DirTreeV2 {
  Filepath(String)
  Dirpath(String, List(DirTreeV2))
}

fn assert_drop_slash(path: String) -> String {
  assert string.starts_with(path, "/")
  path
}

fn assert_drop_all(paths: List(String)) -> List(String) {
  list.map(paths, assert_drop_slash)
}

fn filter_empty(paths: List(String)) -> List(String) {
  list.filter(paths, fn(p) {p != ""})
}

fn directory_contents_internal(
  previous: List(DirTreeV2),
  under_construction: Option(#(String, List(String))),
  remaining: List(String),
) -> List(DirTreeV2) {
  let pass_files_on = fn(files: List(String)) {
    files
    |> assert_drop_all
    |> filter_empty
    |> list.reverse
  }

  case remaining, under_construction {
    [], None -> previous |> list.reverse
    [], Some(#(name, [])) -> {
      let constructed = Filepath(name)
      [constructed, ..previous] |> list.reverse
    }
    [], Some(#(name, files)) -> {
      let constructed = Dirpath(
        name,
        directory_contents_internal([], None, files |> pass_files_on),
      )
      [constructed, ..previous] |> list.reverse
    }
    [first, ..rest], None -> {
      let under_construction = case string.split_once(first, "/") |> result.unwrap(#(first, "")) {
        #(dirname, path) if path != "" -> Some(#(dirname, [path]))
        #(dirname, _) -> Some(#(dirname, []))
      }
      directory_contents_internal(previous, under_construction, rest)
    }
    [first, ..rest], Some(#(name, files)) -> {
      case string.split_once(first, "/") |> result.unwrap(#(first, "")) {
        #(dirname, path) if dirname == name -> {
          let assert True = path != ""
          directory_contents_internal(previous, Some(#(name, [path, ..files])), rest)
        }
        #(dirname, path) -> {
          let constructed = DirTree(
            name: name,
            contents: directory_contents_internal([], None, files |> list.reverse),
          )
          let under_construction = case path == "" {
            True -> Some(#(dirname, []))
            False -> Some(#(dirname, [path]))
          }
          directory_contents_internal([constructed, ..previous], under_construction, rest)
        }
      }
    }
  }
}

pub fn try_again(
  previous: List(DirTreeV2),
  under_construction: Option(#(String, List(List(String)))),
  remaining: List(List(String)),
) -> List(DirTreeV2) {
  let package_current = fn(name: String, decomposed_paths) {
    let subdirs = try_again([], None, decomposed_paths)
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
        [filename] -> {
          let constructed = Filepath(filename)
          try_again([constructed, ..previous], None, rest)
        }
        [dirname, ..decomposed_path] -> {
          try_again(previous, Some(#(dirname, [decomposed_path])), rest)
        }
      }
    }

    [first, ..rest], Some(#(name, decomposed_paths)) -> {
      case first {
        [] -> panic

        [filename] -> {
          assert filename != name
          let constructed1 = package_current(name, decomposed_paths)
          let constructed2 = Filepath(filename)
          try_again(
            [constructed2, constructed1, ..previous],
            None,
            rest,
          )
        }

        [dirname, ..decomposed_path] if dirname == name -> {
          try_again(
            previous,
            Some(#(name, [decomposed_path, ..decomposed_paths])),
            rest,
          )
        }

        [dirname, ..decomposed_path] if dirname != name -> {
          let constructed1 = package_current(name, decomposed_paths)
          try_again(
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
  Dirpath(
    dirname,
    try_again([], None, paths)
  )
}

pub fn main() {
  
}

// fn directory_pretty_printer_add_margin(
//   lines: List(String),
//   is_last: Bool,
// ) -> List(String) {
//   let t = "├─ "
//   let b = "│  "
//   let l = "└─ "
//   let s = "   "
//   case is_last {
//     False -> list.index_map(
//       lines,
//       fn (line, i) {
//         case i == 0 {
//           True -> t <> line
//           False -> b <> line
//         }
//       }
//     )
//     True -> list.index_map(
//       lines,
//       fn (line, i) {
//         case i == 0 {
//           True -> l <> line
//           False -> s <> line
//         }
//       }
//     )
//   }
// }

pub fn pretty_printer(tree: DirTreeV2) -> List(String) {
  case tree {
    Filepath(path) -> [path]
    Dirpath(path, children) -> {
      let num_children = children |> list.length
      let xtra_margin = case string.reverse(tree.name) |> string.split_once("/") {
        Ok(#(_, after)) -> string.length(after) + 1
        _ -> 0
      }
      let xtra_margin = string.repeat(" ", xtra_margin)
      list.index_map(
        tree.contents,
        fn (child, i) {
          pretty_printer(child)
          |> directory_pretty_printer_add_margin(i == num_children - 1)
          |> list.map(fn(line){xtra_margin <> line})
        }
      )
      |> list.flatten
      |> list.prepend(tree.name)

    }
  }
}
