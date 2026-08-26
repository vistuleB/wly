import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError, DesugaringError,
}
import desugaring/nodemaps_2_transform as n2t
import gleam/io
import gleam/list
import gleam/result
import gleam/string.{inspect as ins}
import on
import shellout
import simplifile
import vxml.{type VXML, V}

pub const name = "delete_files_not_used_as_src"

const whoami = "  " <> name

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Deletes image files whose paths are not referenced by a
/// `src` attribute on any configured element tag.
pub fn constructor(param: Param) -> Desugarer {
  authoring.desugarer(
    name: name,
    param: param,
    prepare: param_to_inner_param,
    transform: inner_param_to_transform,
  )
}

type Param =
  #(
    // Execution directory containing the files.
    String,
    // Image directory relative to the execution directory.
    String,
    // File extensions eligible for deletion.
    List(String),
    // Element tags whose `src` attributes count as uses.
    List(String),
  )

type InnerParam {
  InnerParam(
    exec_dir: String,
    img_dir: String,
    extensions: List(String),
    src_tags: List(String),
  )
}

type State =
  List(String)

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(InnerParam(
    exec_dir: param.0 |> core.drop_suffix("/"),
    img_dir: param.1 |> core.drop_suffix("/"),
    extensions: case param.2 {
      [] -> ["svg", "png", "jpg", "jpeg", "gif"]
      extensions -> extensions
    },
    src_tags: param.3,
  ))
}

fn inner_param_to_transform(inner: InnerParam) -> DesugarerTransform {
  let at_root = at_root(_, inner)
  at_root |> n2t.node_to_nil_2_desugarer_transform_without_walking()
}

fn at_root(root: VXML, inner: InnerParam) -> Result(Nil, DesugaringError) {
  let srcs =
    n2t.stateful_no_error_visit(root, [], fn(a, b) { nodemap(a, b, inner) })
    |> list.map(core.drop_prefix(_, "/"))

  let exec_dir_to_img_dir = case inner.img_dir {
    "" -> inner.exec_dir
    _ -> inner.exec_dir <> "/" <> inner.img_dir
  }

  use paths <- on.error_ok(simplifile.get_files(exec_dir_to_img_dir), fn(err) {
    Error(DesugaringError(
      authoring.blame(name, 87),
      "unable to load files in '"
        <> inner.exec_dir
        <> "': "
        <> simplifile.describe_error(err),
    ))
  })

  let extensions = list.map(inner.extensions, core.ensure_prefix(_, "."))
  let ends_correctly = fn(filename) -> Bool {
    list.any(extensions, string.ends_with(filename, _))
  }
  let is_not_used = fn(filename) -> Bool { !list.contains(srcs, filename) }
  let should_be_deleted = fn(filename) -> Bool {
    is_not_used(filename) && ends_correctly(filename)
  }

  paths
  |> list.map(core.assert_drop_prefix(_, inner.exec_dir <> "/"))
  |> list.filter(should_be_deleted)
  |> list.try_each(fn(path) {
    let full_path = inner.exec_dir <> "/" <> path
    let cmd = "rm " <> full_path
    io.println(whoami <> ": " <> cmd)
    shellout.command(run: "rm", with: [full_path], in: ".", opt: [])
    |> result.map_error(fn(error) {
      DesugaringError(
        authoring.blame(name, 114),
        "failed to delete " <> full_path <> " (" <> ins(error) <> ")",
      )
    })
  })
}

fn nodemap(vxml: VXML, state: State, inner: InnerParam) -> State {
  use #(tag, attrs) <- on.stay(case vxml {
    V(_, tag, attrs, _) -> on.Stay(#(tag, attrs))
    _ -> on.Return(state)
  })

  use <- on.eager_false_true(list.contains(inner.src_tags, tag), state)

  attrs
  |> list.filter(fn(attr) { attr.key == "src" })
  |> list.map(fn(attr) { attr.val })
  |> core.pour(state)
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊

fn assertive_tests_data() -> List(core.AssertiveTestData(Param)) {
  []
}

pub fn assertive_tests() {
  core.assertive_test_collection_from_data(
    name,
    assertive_tests_data(),
    constructor,
  )
}
