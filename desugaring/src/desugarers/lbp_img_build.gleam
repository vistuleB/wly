import gleam/dict.{type Dict}
import gleam/dynamic/decode
import gleam/float
import gleam/function
import gleam/int
import gleam/io
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import blame
import filepath
import infrastructure.{type Desugarer, Desugarer, type DesugaringError, DesugaringError, type DesugarerTransform} as infra
import nodemaps_2_desugarer_transforms as n2t
import on
import shellout
import simplifile
import vxml.{type VXML, type Attr, V}

fn build_img_info_to_json(info: BuildImgInfo) -> json.Json {
  json.object([
    #("build-version", json.string(info.build_version_path)),
    #("build-version-created-on", json.int(info.build_version_created_on)),
    #("build-version-size", json.int(info.build_version_size)),
    #("original-size", json.int(info.original_size)),
    #("compression", json.string(info.compression)),
    #("used-last-build", json.bool(info.used_last_build)),
  ])
}

fn build_dictionary_to_json(dict: BuildDictionary) -> json.Json {
  dict
  |> dict.to_list()
  |> list.map(fn(kv) { #(kv.0, build_img_info_to_json(kv.1)) })
  |> json.object()
}

fn json_to_build_img_info() -> decode.Decoder(BuildImgInfo) {
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

fn json_to_build_dictionary() -> decode.Decoder(BuildDictionary) {
  decode.dict(decode.string, json_to_build_img_info())
}

fn load_build_dictionary(image_map: String) -> BuildDictionary {
  case simplifile.is_file(image_map) {
    Ok(True) -> {
      case simplifile.read(image_map) {
        Ok(content) -> {
          content
          |> json.parse(json_to_build_dictionary())
          |> on.ok_error(function.identity,
          fn(err) {
            io.println("JSON cannot be parsed. Error " <> string.inspect(err))
            io.println("New BuildDictionary is constructed")
            dict.new()
          }
          )
        }
        Error(err) -> {
          io.println("File " <> image_map <> " cannot be read. Error is " <> simplifile.describe_error(err))
          io.println("New BuildDictionary is constructed")
          dict.new()
        }
      }
    }
    _ -> {
      io.println("File " <> image_map <> " does not exist")
      io.println("New BuildDictionary is constructed")
      dict.new()
    }
  }
}

fn save_build_dictionary(dict: BuildDictionary, image_map_path: String) -> Result(Nil, simplifile.FileError) {
  let abs_path = case simplifile.current_directory() {
    Ok(cwd) -> Ok(cwd <> "/" <> image_map_path)
    Error(err) -> Error(err)
  }
  let json_content = build_dictionary_to_json(dict) |> json.to_string()

  abs_path
  |> on.ok(fn(abs_path) { simplifile.write(abs_path, json_content)})
}

fn last_modified_date(file_path: String) -> Int {
  case simplifile.file_info(file_path) {
    Ok(info) -> info.mtime_seconds
    Error(_) -> 0 // fallback to epoch time if we can't read file info
  }
}

fn construct_source_dictionary(images_dir: String) -> Result(SourceDictionary, DesugaringError) {
      simplifile.get_files(images_dir)
      |> result.map(fn(images) {
        images
        |> list.map(fn(img) {
          #(img, last_modified_date(img))
        })
      })
      |> result.map(dict.from_list)
      |> result.map_error(fn(err) { DesugaringError(blame.no_blame, simplifile.describe_error(err)) })
}

fn get_created_date(path: String) -> Result(Int, simplifile.FileError) {
  use info <- result.try(simplifile.file_info(path))
  Ok(info.ctime_seconds)
}

fn get_file_size(path: String) -> Result(Int, simplifile.FileError) {
  use info <- result.try(simplifile.file_info(path))
  Ok(info.size)
}

fn calculate_compression_percentage(original_size: Int, new_size: Int) -> String {
  case original_size {
    0 -> "0%"
    _ -> {
      let compression = int.to_float(original_size - new_size) /. int.to_float(original_size) *. 100.0
      float.to_string(compression) <> "%"
    }
  }
}

//*** Unused helper functions

// wly source files refer images with `images/1.svg`
// rather than `../public/images/1.svg` which is the path
// used in Source and Build dictionaries
// this function add prefix ../public to the src url
fn add_public_prefix(s: String) -> String {
  let image_dir_prefix = "../public/"
  case !string.starts_with(s, image_dir_prefix <> "images/") && string.starts_with(s, "images/") {
    True -> string.concat([image_dir_prefix, s])
    False -> s
  }
}

fn remove_public_prefix(s: String) -> String {
  let prefix = "../public/"
  case string.starts_with(s, prefix) {
    True -> string.drop_start(s, string.length(prefix) - 1)
    False -> s
  }
}

fn resolve_relative_img_path(abs_path: String, image_path: String) -> String {
  let filename = abs_path
    |> string.split("/")
    |> list.last()
    |> result.unwrap("")

  image_path <> "/" <> filename
}

fn resolve_path(relative_path: String) -> Result(String, DesugaringError) {
  case simplifile.current_directory() {
    Ok(cwd) -> Ok(cwd <> "/" <> relative_path)
    Error(err) -> Error(DesugaringError(blame.no_blame, "Unable to resolve path " <> relative_path <> ". Error " <> simplifile.describe_error(err)))
  }
}

/////////////////////////

fn go_up_a_level(s: String) -> String {
  case string.starts_with(s, "images/") {
    True -> string.concat(["../", s])
    False -> s
  }
}

fn remove_trailing_slash(path: String) -> String {
  case string.ends_with(path, "/") {
    True -> string.drop_end(path, 1)
    False -> path
  }
}

fn sanitize_path_in_param(param: Param) -> Param {
  let #(images_dir, build_dir, image_map_path, opt_build_dict, opt_source_dict) = param

  #(remove_trailing_slash(images_dir), remove_trailing_slash(build_dir), remove_trailing_slash(image_map_path), opt_build_dict, opt_source_dict)
}

fn relative_src_path(src: String) -> String {
  src
  |> infra.drop_prefix("./")
  |> infra.drop_prefix("/")
  |> go_up_a_level()
}

fn should_optimize_svg(attrs: List(Attr)) -> Bool {
  !list.any(attrs, fn(attr) {
    attr.key == "svgo" && attr.val == "false"
  })
}

fn remove_svgo_attribute(vxml: VXML) -> VXML {
  case vxml {
    V(blame, tag, attrs, children) -> V(blame, tag, infra.attrs_delete(attrs, "svgo"), children)
    t -> t
  }
}

fn img_extension(image_path: String) -> Result(String, DesugaringError) {
  let supported_extensions = ["svg", "png", "jpg", "jpeg", "gif", "webp"]

  image_path
  |> string.split(".")
  |> list.last()
  |> on.ok_error(
      fn(ext) {
        on.true_false(
          list.contains(supported_extensions, ext),
          Ok(ext),
          fn() { Error(DesugaringError(blame.no_blame, "Image extension is not one of supported extensions (" <> string.join(supported_extensions, ", " <> " )"))) }
        )
      },
      fn(_) { Error(DesugaringError(blame.no_blame, "Image " <> image_path <> " must have an extension")) }
  )
}

fn create_svg_build_dir_if_missing(build_path: String) -> Result(String, DesugaringError) {
  let svg_build_dir = "build-svg-o"
  let relative_svg_build_dir_path = build_path <> "/" <> svg_build_dir

  case simplifile.is_directory(relative_svg_build_dir_path) {
    Ok(True) -> {
      Ok(relative_svg_build_dir_path)
    }
    _ -> {
       simplifile.create_directory_all(relative_svg_build_dir_path)
       |> on.ok_error(
         fn(_) { Ok(relative_svg_build_dir_path) },
         fn(err) { Error(DesugaringError(blame.no_blame, "Error " <> simplifile.describe_error(err) <> " trying to create directory " <> relative_svg_build_dir_path))}
       )
    }
  }
}

@external(erlang, "erlang", "system_time")
fn erlang_system_time() -> Int

pub fn get_random_filename() -> String {
  let timestamp = erlang_system_time()
  int.to_string(timestamp)
}

type OptimizedImgPath = String

fn optimize_svg(build_svg_dir: String, image: String) -> Result(#(OptimizedImgPath, BuildImgInfo), DesugaringError) {
  let optimized_img = build_svg_dir <> "/" <> get_random_filename() <> ".svg"

  // run svgo
  let svgo_result = shellout.command(
    run: "svgo",
    with: [image, "-o", optimized_img],
    in: ".",
    opt: []
  )

  use created_date <- result.try(case svgo_result {
    Ok(_) -> {
      case get_created_date(optimized_img) {
        Ok(created_date) -> Ok(created_date)
        Error(err) -> Error(DesugaringError(
          blame.no_blame,
          "Could not get created date of optimized image: " <> optimized_img <> ": " <> simplifile.describe_error(err)
        ))
      }
    }
    Error(err) -> Error(DesugaringError(
      blame.no_blame,
      "svgo command failed for " <> image <> ": " <> string.inspect(err)
    ))
  })

  use original_size <- result.try(case get_file_size(image) {
    Ok(val) -> Ok(val)
    Error(_) -> Error(DesugaringError(
      blame.no_blame,
      "Could not get size of original image: " <> image
    ))
  })

  use new_size <- result.try(case get_file_size(optimized_img) {
    Ok(val) -> Ok(val)
    Error(_) -> Error(DesugaringError(
      blame.no_blame,
      "Could not get size of optimized image: " <> optimized_img
    ))
  })

  let compression = calculate_compression_percentage(original_size, new_size)
  #(optimized_img, BuildImgInfo(
    build_version_path: optimized_img,
    build_version_created_on: created_date,
    build_version_size: new_size,
    original_size: original_size,
    compression: compression,
    used_last_build: True,
  ))
  |> Ok
}

fn build_image(build_dict: BuildDictionary, attrs: List(Attr), image: String, build_path: String) -> Result(#(Option(OptimizedImgPath), BuildDictionary), DesugaringError) {
  case image |> img_extension {
    Ok("svg") -> {
      case should_optimize_svg(attrs) {
        True -> {
          build_path
          |> create_svg_build_dir_if_missing()
          |> on.ok(fn(svg_build_dir) { optimize_svg(svg_build_dir, image) })
          |> on.ok(fn(pair) { #(Some(pair.0), dict.insert(build_dict, image, pair.1)) |> Ok })
        }
        False -> {
          // remove current entry from build dict since `svgo=false`
          dict.delete(build_dict, image)
          |> fn(updated_dict) { Ok(#(None, updated_dict)) }
        }
      }
    }
    // for all other image type, we ignore optimisation
    _ -> Ok(#(None, build_dict))
  }
}

fn update_img_src(img: VXML, src: OptimizedImgPath) -> VXML {
  infra.v_set_attr(img, blame.no_blame, "src", src)
}

fn v_before(
  vxml: VXML,
  build_dict: BuildDictionary,
  inner_param: InnerParam,
) -> Result(#(VXML, BuildDictionary), DesugaringError) {
  let assert V(_, tag, attrs, _) = vxml
  let relative_build_path = inner_param.1
  let image_tags = ["img", "Image", "ImageLeft", "ImageRight"]

  use <- on.true_false(!list.contains(image_tags, tag), Ok(#(vxml, build_dict)))

  let #(_images_dir, _build_dir, _image_map_path, source_dict) = inner_param

  case list.find(attrs, fn(attr: Attr) { attr.key == "src" }) {
    Ok(src_attr) -> {
      let relative_image_path = relative_src_path(src_attr.val)

      case dict.get(source_dict, relative_image_path), dict.get(build_dict, relative_image_path) {
        Ok(last_modified), Ok(build_img) -> {
          case last_modified > build_img.build_version_created_on {
            True -> {
              // since image modified date is greater than the last build,
              // we rebuild the image
              build_dict
              |> build_image(attrs, relative_image_path, relative_build_path)
              |> result.map(fn(pair) {
                let optimized_img_path = pair.0
                let updated_build_dict = pair.1
                on.some_none(optimized_img_path,
                  fn(o_img_path) { #(
                    vxml
                    |> update_img_src(o_img_path)
                    |> remove_svgo_attribute(),
                    updated_build_dict)
                  },
                  fn() {#(vxml |> remove_svgo_attribute(), updated_build_dict)}
                )
              })
            }
            False -> Ok(#(vxml |> remove_svgo_attribute(), build_dict))
          }
        }
        Ok(_source_last_modified), Error(Nil) -> {
          // image is in source but not in build so we build one
          build_dict
          |> build_image(attrs, relative_image_path, relative_build_path)
          |> result.map(fn(pair) {
            let optimized_img_path = pair.0
            let updated_build_dict = pair.1
            on.some_none(optimized_img_path,
              fn(o_img_path) { #(
                vxml
                |> update_img_src(o_img_path)
                |> remove_svgo_attribute(),
                updated_build_dict)
              },
              fn() {#(vxml |> remove_svgo_attribute(), updated_build_dict)}
            )
          })
        }
        Error(Nil), Ok(_build_img) -> {
          // image is in build but not in source (possibly deleted)
          // we ignore in this case and leave build_img data alone
          Ok(#(vxml |> remove_svgo_attribute(), build_dict))
        }
        Error(Nil), Error(Nil) -> {
          // image is in neither build nor in source
          // i.e. image do not exist
          Ok(#(vxml |> remove_svgo_attribute(), build_dict))
        }
      }
    }
    Error(Nil) -> Ok(#(vxml |> remove_svgo_attribute(), build_dict))
  }
}

// TODO:
// 2. handle other optimizations for remaining image types.
// 3. remove hardcoded dependency on image_path and build_path. Make it generic and so everything takes them as param

fn v_after(
  vxml: VXML,
  ancestors: List(VXML),
  state: BuildDictionary,
  inner: InnerParam,
) -> Result(#(VXML, BuildDictionary), DesugaringError) {
  case ancestors {
    [] -> {
      case save_build_dictionary(state, inner.2) {
        Ok(Nil) -> Ok(#(vxml, state))
        Error(err) -> Error(DesugaringError(blame.no_blame, "Unable to save " <> inner.2 <> ". Error " <> simplifile.describe_error(err)))
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

fn transform_factory(inner: InnerParam, build_dict: Option(BuildDictionary)) -> DesugarerTransform {
  let init_state = on.some_none(build_dict, function.identity, fn() { load_build_dictionary(inner.2)})
  n2t.fancy_one_to_one_before_and_after_stateful_nodemap_2_desugarer_transform(
    nodemap_factory(inner),
    init_state
  )
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  let #(images_dir, build_dir, image_map_path, _, opt_source_dict) = param

  case simplifile.is_directory(images_dir) {
    Ok(True) -> {
      case opt_source_dict {
        Some(dict) -> Ok(#(images_dir, build_dir, image_map_path, dict))
        None -> {
          construct_source_dictionary(images_dir)
          |> result.map(fn(dict) { #(images_dir, build_dir, image_map_path, dict) })
        }
      }
    }
    Ok(False) -> Error(DesugaringError(blame.no_blame, "images directory " <> images_dir <> " does not exist"))
    Error(err) -> Error(DesugaringError(blame.no_blame, simplifile.describe_error(err)))
  }
}

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

pub type BuildDictionary = Dict(String, BuildImgInfo)
pub type SourceDictionary = Dict(String, Int) // path -> last_modified timestamp
pub type State = BuildDictionary

type Param = #(String,     String,     String, Option(BuildDictionary), Option(SourceDictionary))
//             ↖            ↖           ↖
//              images_path  build_path  image-map.json
type InnerParam = #(String,       String,     String, SourceDictionary)
//                  ↖             ↖           ↖
//                   images_path   build_path  image-map.json

pub const name = "lbp_img_build"

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
    stringified_param: Some("(" <> param.0 <> ", " <> param.1 <> ", " <> param.2 <> ")"),
    stringified_outside: option.None,
    transform: case param_to_inner_param(sanitize_path_in_param(param)) {
      Error(error) -> fn(_) { Error(error) }
      Ok(inner) -> transform_factory(inner, param.3)
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
