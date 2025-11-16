import gleam/io
import gleam/list
import gleam/option
import gleam/result
import gleam/string.{inspect as ins}
import blame as bl
import infrastructure.{
  type Desugarer,
  type DesugaringError,
  type DesugarerTransform,
  Desugarer,
  DesugaringError,
} as infra
import nodemaps_2_desugarer_transforms as n2t
import on
import shellout
import simplifile
import vxml.{type VXML, V}

const whoami = "  " <> name

fn collector(
  vxml: VXML,
  state: State,
  inner: InnerParam,
) -> State {
  use #(tag, attrs) <- on.continue(case vxml {
    V(_, tag, attrs, _) -> on.Continue(#(tag, attrs))
    _ -> on.Return(state)
  })

  use <- on.false_true(
    list.contains(inner.3, tag),
    state,
  )

  attrs
  |> list.filter(fn(attr) { attr.key == "src" })
  |> list.map(fn(attr) { attr.val })
  |> infra.pour(state)
}

fn at_root(
  root: VXML,
  inner: InnerParam,
) -> Result(Nil, DesugaringError) {
  let srcs = n2t.no_error_information_collector_walk(
    root,
    [],
    fn(a, b) { collector(a, b, inner) },
  )
  |> list.map(infra.drop_prefix(_, "/"))

  let exec_dir_to_img_dir = case inner.1 {
    "" -> inner.0
    _ -> inner.0 <> "/" <> inner.1
  }

  use paths <- on.error_ok(
    simplifile.get_files(exec_dir_to_img_dir),
    fn(err) {
      Error(DesugaringError(
        desugarer_blame(126),
        "unable to load files in '" <> inner.0 <> "': " <> simplifile.describe_error(err))
      )
    }
  )

  let extensions = list.map(
    inner.2,
    infra.ensure_prefix(_, "."),
  )

  let ends_correctly = fn(filename) -> Bool {
    list.any(extensions, string.ends_with(filename, _))
  }

  let is_not_used = fn(filename) -> Bool {
    !list.contains(srcs, filename)
  }

  let should_be_deleted = fn(filename) -> Bool {
    is_not_used(filename) && ends_correctly(filename)
  }

  paths
  |> list.map(infra.assert_drop_prefix(_, inner.0 <> "/"))
  |> list.filter(should_be_deleted)
  |> list.try_each(fn(p) {
    let cmd = "rm " <> inner.0 <> "/" <> p
    io.println(whoami <> ": " <> cmd)
    shellout.command(
      run: "rm",
      with: [inner.0 <> "/" <> p],
      in: ".",
      opt: [],
    )
    |> result.map_error(fn(e) {
      DesugaringError(desugarer_blame(0), "failed to delete " <> inner.0 <> "/" <> p <> " (" <> ins(e) <> ")")
    })
  })
}

fn transform_factory(inner: InnerParam) -> DesugarerTransform {
  at_root(_, inner)
  |> n2t.at_root_no_changes_2_desugarer_transform()
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(#(
    param.0 |> infra.drop_suffix("/"),
    param.1 |> infra.drop_suffix("/"),
    case param.2 {
      [] -> ["svg", "png", "jpg", "jpeg", "gif"]
      _ -> param.2
    },
    param.3,
  ))
}

type State = List(String)

type Param = #(
  String,       // exec_dir_to_build_dir
  String,       // build_dir_to_build_img_dir
  List(String), // delete only files with these extensions
  List(String), // if no tag in this list ever mentions that src
)
type InnerParam = Param

pub const name = "delete_files_not_used_as_src"
fn desugarer_blame(line_no: Int) -> bl.Blame { bl.Des([], name, line_no) }

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// Processes images for build: optimizes SVGs with svgo,
/// copies other images, maintains build dictionary with
/// compression stats and timestamps
pub fn constructor(param: Param) -> Desugarer {
  Desugarer(
    name: name,
    stringified_param: option.Some(ins(param)),
    stringified_outside: option.None,
    transform: case param_to_inner_param(param) {
      Error(error) -> fn(_) { Error(error) }
      Ok(inner) -> transform_factory(inner)
    },
  )
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊

fn assertive_tests_data() -> List(infra.AssertiveTestData(Param)) {
  []
}

pub fn assertive_tests() {
  infra.assertive_test_collection_from_data(name, assertive_tests_data(), constructor)
}
