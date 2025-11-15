import gleam/dict.{type Dict}
import gleam/dynamic/decode
import gleam/float
import gleam/int
import gleam/io
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string.{inspect as ins}
import blame.{type Blame} as bl
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
import vxml.{type VXML, type Attr, V}

// fn build_img_info_to_json(info: BuildImgInfo) -> json.Json {
//   json.object([
//     #("build-version", json.string(info.build_version_path)),
//     #("build-version-created-on", json.int(info.build_version_created_on)),
//     #("build-version-size", json.int(info.build_version_size)),
//     #("original-size", json.int(info.original_size)),
//     #("compression", json.string(info.compression)),
//     #("used-last-build", json.bool(info.used_last_build)),
//   ])
// }

// fn build_dictionary_to_json(dict: ImageMap) -> json.Json {
//   dict
//   |> dict.to_list()
//   |> list.map(fn(kv) { #(kv.0, build_img_info_to_json(kv.1)) })
//   |> json.object()
// }

fn build_img_info_pretty_string(key: String, info: BuildImgInfo, indent: Int, indentation: Int) -> String {
  let margin1 = string.repeat(" ", indent)
  let margin2 = string.repeat(" ", indent + indentation)
  margin1 <> "\"" <> key <> "\": {\n"
  <> margin2 <> "\"build-version\": " <> { json.string(info.build_version_path) |> json.to_string } <> ",\n"
  <> margin2 <> "\"build-version-created-on\": " <> { json.int(info.build_version_created_on) |> json.to_string } <> ",\n"
  <> margin2 <> "\"build-version-size\": " <> { json.int(info.build_version_size) |> json.to_string } <> ",\n"
  <> margin2 <> "\"original-size\": " <> { json.int(info.original_size) |> json.to_string } <> ",\n"
  <> margin2 <> "\"compression\": " <> { json.string(info.compression) |> json.to_string } <> ",\n"
  <> margin2 <> "\"used-last-build\": " <> { json.bool(info.used_last_build) |> json.to_string } <> "\n"
  <> margin1 <> "}"
}

fn image_map_to_pretty_string(image_map: ImageMap, indentation: Int) -> String {
  let entries =
    image_map
    |> dict.to_list()
    |> list.map(fn(kv) { build_img_info_pretty_string(kv.0, kv.1, indentation, indentation) })
    |> string.join(",\n")
  "{\n" <> entries <> "\n}\n" 
}

fn build_img_info_decoder() -> decode.Decoder(BuildImgInfo) {
  use build_version_path <- decode.field("build-version", decode.string)
  use build_version_created_on <- decode.field("build-version-created-on", decode.int)
  use build_version_size <- decode.field("build-version-size", decode.int)
  use original_size <- decode.field("original-size", decode.int)
  use compression <- decode.field("compression", decode.string)
  use used_last_build <- decode.field("used-last-build", decode.bool)

  decode.success(BuildImgInfo(
    build_version_path: build_version_path,
    build_version_created_on: build_version_created_on,
    build_version_size: build_version_size,
    original_size: original_size,
    compression: compression,
    used_last_build: used_last_build,
  ))
}

fn image_map_decoder() -> decode.Decoder(ImageMap) {
  decode.dict(decode.string, build_img_info_decoder())
}

fn load_image_map(image_map_path: String) -> ImageMap {
  case simplifile.is_file(image_map_path) {
    Ok(True) -> {
      case simplifile.read(image_map_path) {
        Ok(content) -> {
          case json.parse(content, image_map_decoder()) {
            Ok(map) -> map
            Error(err) -> {
              io.println("JSON cannot be parsed. Error " <> string.inspect(err))
              io.println("New ImageMap is constructed")
              dict.new()
            }
          }
        }
        Error(err) -> {
          io.println("File " <> image_map_path <> " cannot be read. Error is " <> simplifile.describe_error(err))
          io.println("New ImageMap is constructed")
          dict.new()
        }
      }
    }
    _ -> {
      io.println("File " <> image_map_path <> " does not exist")
      io.println("New ImageMap is constructed")
      dict.new()
    }
  }
}

fn save_image_map(dict: ImageMap, exec_to_image_map_path: String) -> Result(Nil, simplifile.FileError) {
  // use exec <- on.ok(simplifile.current_directory())
  // let abs_path = exec <> "/" <> exec_to_image_map_path
  let content = image_map_to_pretty_string(dict, 2)
  simplifile.write(exec_to_image_map_path, content)
}

fn last_modified_date(file_path: String) -> Int {
  case simplifile.file_info(file_path) {
    Ok(info) -> info.mtime_seconds
    Error(_) -> 0 // fallback to epoch time if we can't read file info
  }
}

fn construct_source_dictionary(images_dir: String) -> Result(SourceDictionary, DesugaringError) {
  use paths <- on.error_ok(
    simplifile.get_files(images_dir),
    fn(err) { Error(DesugaringError(desugarer_blame(114), simplifile.describe_error(err))) }
  )
  paths
  |> list.map( fn(path) { #(path, last_modified_date(path)) })
  |> dict.from_list
  |> Ok
}

fn get_created_date(path: String) -> Result(Int, simplifile.FileError) {
  use info <- result.try(simplifile.file_info(path))
  Ok(info.ctime_seconds)
}

fn get_file_size(path: String) -> Result(Int, simplifile.FileError) {
  use info <- result.try(simplifile.file_info(path))
  Ok(info.size)
}

fn compression_pct_string(original_size: Int, new_size: Int) -> String {
  case original_size {
    0 -> panic
    _ -> {
      let original_size = int.to_float(original_size)
      let new_size = int.to_float(new_size)
      let savings = original_size -. new_size
      let compression = 100.0 *. savings /. original_size
      compression |> float.to_precision(2) |> float.to_string() <> "%"
    }
  }
}

fn is_svg_optimization_suppressed(attrs: List(Attr)) -> Bool {
  list.any(attrs, fn(a) { a.key == "svgo" && a.val == "false" })
}

fn remove_svgo_attribute(vxml: VXML) -> VXML {
  case vxml {
    V(blame, tag, attrs, children) -> V(blame, tag, infra.attrs_delete(attrs, "svgo"), children)
    t -> t
  }
}

fn img_extension(src: String, blame: Blame) -> Result(String, DesugaringError) {
  use extension <- on.error_ok(
    src |> string.split(".") |> list.last,
    fn(_) { Error(DesugaringError(blame, "image src missing extension: " <> src)) },
  )

  case list.contains(supported_extensions, extension) {
    True -> Ok(extension)
    False -> Error(DesugaringError(blame, "unsupported extension: ." <> extension))
  }
}

@external(erlang, "erlang", "system_time")
fn erlang_system_time() -> Int

fn get_random_filename() -> String {
  erlang_system_time() |> int.to_string
}

fn finish_off_build_image(
  exec_to_src_image_path: String,
  exec_to_build_image_path: String,
  build_dir_to_image_path: String,
) -> Result(BuildImgInfo, DesugaringError) {
  use created_date <- on.error_ok(
    get_created_date(exec_to_build_image_path),
    fn(err) {
      Error(DesugaringError(
        desugarer_blame(237),
        "could not get created date of optimized image: " <> exec_to_build_image_path <> ": " <> simplifile.describe_error(err),
      ))
    }
  )

  use original_size <- on.error_ok(
    get_file_size(exec_to_src_image_path),
    fn(_) {
      Error(DesugaringError(
        desugarer_blame(247),
        "Could not get size of original image: " <> exec_to_src_image_path,
      ))
    }
  )

  use new_size <- on.error_ok(
    get_file_size(exec_to_build_image_path),
    fn(_) {
      Error(DesugaringError(
        desugarer_blame(257),
        "Could not get size of build image: " <> exec_to_build_image_path,
      ))
    }
  )

  let compression = compression_pct_string(original_size, new_size)

  BuildImgInfo(
    build_version_path: build_dir_to_image_path,
    build_version_created_on: created_date,
    build_version_size: new_size,
    original_size: original_size,
    compression: compression,
    used_last_build: True,
  )
  |> Ok
}

fn build_image_via_svgo(
  exec_to_src_image_path: String,
  exec_to_build_dir_path: String,
  build_dir_to_image_path: String,
) -> Result(BuildImgInfo, DesugaringError) {
  let exec_to_build_image_path = exec_to_build_dir_path <> "/" <> build_dir_to_image_path
  let cmd = "svgo " <> exec_to_src_image_path <> " -o " <> exec_to_build_image_path

  io.println("  running: " <> cmd)

  use _ <- on.error_ok(
    shellout.command(
      run: "svgo",
      with: [exec_to_src_image_path, "-o", exec_to_build_image_path],
      in: ".",
      opt: [],
    ),
    fn(err) {
      Error(DesugaringError(desugarer_blame(292), "failed to execute: '" <> cmd <> "' (error: " <> string.inspect(err) <> ")" ))
    },
  )

  finish_off_build_image(
    exec_to_src_image_path,
    exec_to_build_image_path,
    build_dir_to_image_path,
  )
}

fn build_image_via_cp(
  exec_to_src_image_path: String,
  exec_to_build_dir_path: String,
  build_dir_to_image_path: String,
) -> Result(BuildImgInfo, DesugaringError) {
  let exec_to_build_image_path = exec_to_build_dir_path <> "/" <> build_dir_to_image_path
  let cmd = "cp " <> exec_to_src_image_path <> " " <> exec_to_build_image_path

  use _ <- on.error_ok(
    shellout.command(
      run: "cp",
      with: [exec_to_src_image_path, exec_to_build_image_path],
      in: ".",
      opt: [],
    ),
    fn(err) {
      Error(DesugaringError(desugarer_blame(319), "failed to execute: '" <> cmd <> "' (error: " <> string.inspect(err) <> ")" ))
    },
  )

  finish_off_build_image(
    exec_to_src_image_path,
    exec_to_build_image_path,
    build_dir_to_image_path,
  )
}

fn update_src_attr(attrs: List(Attr), src: String) -> List(Attr) {
  infra.attrs_set(attrs, desugarer_blame(427), "src", "/" <> src)
}

fn create_dirs_on_path_to_file(path_to_file: String) -> Result(Nil, simplifile.FileError) {
  let pieces = path_to_file |> string.split("/")
  let pieces = infra.drop_last(pieces)
  list.try_fold(pieces, ".", fn(acc, piece) {
    let acc = acc <> "/" <> piece
    use exists <- on.ok(simplifile.is_directory(acc))
    use _ <- on.ok(
      case exists {
        True  -> Ok(Nil)
        False -> simplifile.create_directory(acc)
      }
    )
    Ok(acc)
  })
  |> result.map(fn(_) { Nil })
}

fn v_before(
  vxml: VXML,
  image_map: ImageMap,
  inner: InnerParam,
) -> Result(#(VXML, ImageMap), DesugaringError) {
  let assert V(_, tag, attrs, _) = vxml
  let source_dict = inner.5

  // escape #1: no 'src' expected:
  use <- on.lazy_false_true(
    list.contains(img_tags, tag),
    fn() { Ok(#(vxml, image_map)) },
  )

  // escape #2: 'src' missing:
  use src_attr <- on.lazy_none_some(
    infra.attrs_first_with_key(attrs, "src"),
    fn() { Ok(#(vxml |> remove_svgo_attribute, image_map)) },
  )

  let src = src_attr.val |> infra.drop_prefix("./") |> infra.drop_prefix("/")

  // escape #3: src does not start with the expected src_dir_to_src_img_dir directory
  use <- on.lazy_false_true(
    string.starts_with(src, inner.2),
    fn() { Ok(#(vxml |> remove_svgo_attribute, image_map)) },
  )

  let src_dict_key = inner.0 <> "/" <> src

  // escape #4: this file does actually not exist; user's problem, we ignore (we KULD generate a warning)
  use last_modified <- on.error_ok(
    dict.get(source_dict, src_dict_key),
    fn(_) { Ok(#(vxml |> remove_svgo_attribute, image_map)) },
  )

  // escape #5: this file exists in the image_map and its image as 
  let #(need_to_do_something, existing_build_img_path) = case dict.get(image_map, src_dict_key) {
    Error(_) -> #(True, "")
    Ok(img_info) -> case last_modified > img_info.build_version_created_on {
      True -> #(True, img_info.build_version_path)
      // MISSING: we should actually check that the build_version exists, here
      False -> #(False, img_info.build_version_path)
    }
  }

  use extension <- on.ok(img_extension(src, src_attr.blame))
  let copy_mode = extension != "svg" || is_svg_optimization_suppressed(attrs)
  let attrs = infra.attrs_delete(attrs, "svgo")

  let builder = case copy_mode {
    True -> build_image_via_cp
    False -> build_image_via_svgo
  }

  use <- on.lazy_false_true(
    need_to_do_something,
    fn () {
      let attrs = update_src_attr(attrs, existing_build_img_path)
      Ok(#(V(..vxml, attrs: attrs), image_map))
    }
  )

  let exec_to_src_image_path = src_dict_key

  let build_img_dir_to_image_path = case copy_mode {
    True -> extension <> "/" <> get_random_filename() <> "." <> extension
    False -> "svgo-svg" <> "/" <> get_random_filename() <> "." <> extension
  }

  let build_dir_to_build_image_path = case inner.3 {
    "" -> build_img_dir_to_image_path
    _ -> inner.3 <> "/" <> build_img_dir_to_image_path
  }

  let exec_to_build_image_path = inner.1 <> "/" <> build_dir_to_build_image_path

  let _ = create_dirs_on_path_to_file(exec_to_build_image_path)

  use img_info <- on.ok(builder(
    exec_to_src_image_path, 
    inner.1,
    build_dir_to_build_image_path,
  ))

  let attrs = update_src_attr(attrs, img_info.build_version_path)
  let image_map = dict.insert(image_map, src_dict_key, img_info)

  Ok(#(V(..vxml, attrs: attrs), image_map))
}

fn v_after(
  vxml: VXML,
  ancestors: List(VXML),
  state: ImageMap,
  inner: InnerParam,
) -> Result(#(VXML, ImageMap), DesugaringError) {
  case ancestors {
    [] -> {
      case save_image_map(state, inner.4) {
        Ok(Nil) -> Ok(#(vxml, state))
        Error(err) -> Error(DesugaringError(desugarer_blame(547), "Unable to save " <> inner.2 <> ". Error " <> simplifile.describe_error(err)))
      }
    }
    _ -> Ok(#(vxml, state))
  }
}

fn nodemap_factory(inner: InnerParam) -> n2t.FancyOneToOneBeforeAndAfterStatefulNodeMap(State) {
   n2t.FancyOneToOneBeforeAndAfterStatefulNodeMap(
    v_before_transforming_children: fn(vxml, _, _, _, _, state) {
      v_before(vxml, state, inner)
    },
    v_after_transforming_children: fn(vxml, ancestors, _, _, _, _, latest_state) {
      v_after(vxml, ancestors, latest_state, inner)
    },
    t_nodemap: fn(vxml, _, _, _, _, state) {
      Ok(#(vxml, state))
    },
  )
}

fn transform_factory(inner: InnerParam) -> DesugarerTransform {
  let image_map = load_image_map(inner.4)
  nodemap_factory(inner)
  |> n2t.fancy_one_to_one_before_and_after_stateful_nodemap_2_desugarer_transform(image_map)
}

fn sanitize_path_in_param(param: Param) -> Param {
  assert !string.starts_with(param.2, "/")
  assert !string.starts_with(param.2, "./")
  assert !string.starts_with(param.2, "../")
  assert !string.starts_with(param.3, "/")
  assert !string.starts_with(param.3, "./")
  assert !string.starts_with(param.3, "../")
  assert string.ends_with(param.4, ".json")
  #(
    param.0 |> infra.drop_suffix("/"),
    param.1 |> infra.drop_suffix("/"),
    param.2 |> infra.drop_suffix("/"),
    param.3 |> infra.drop_suffix("/"),
    param.4,
  )
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  let param = sanitize_path_in_param(param)
  use source_dict <- on.ok(construct_source_dictionary(param.0))
  Ok(#(param.0, param.1, param.2, param.3, param.4, source_dict))
}

const img_tags = ["img", "Image", "ImageLeft", "ImageRight"]
const supported_extensions = ["svg", "png", "jpg", "jpeg", "gif", "webp"]

pub type BuildImgInfo {
  BuildImgInfo(
    build_version_path: String,
    build_version_created_on: Int,
    build_version_size: Int,
    original_size: Int,
    compression: String, // e.g. "38.85%"
    used_last_build: Bool,
  )
}

pub type ImageMap = Dict(String, BuildImgInfo)
pub type SourceDictionary = Dict(String, Int) // path -> last_modified timestamp
pub type State = ImageMap

type Param = #(
  String, // exec_dir_to_src_dir
  String, // exec_dir_to_build_dir
  String, // src_dir_to_src_img_dir
  String, // build_dir_to_build_img_dir
  String, // path_to_image_map.json
)

type InnerParam = #(
  String,
  String,
  String,
  String,
  String,
  SourceDictionary,
)

pub const name = "lbp_img_build"
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
    stringified_param: Some(ins(#(param.0, param.1, param.2, param.3, param.4))),
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
