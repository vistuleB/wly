import gleam/bit_array
import gleam/dict.{type Dict}
import gleam/dynamic/decode
import gleam/float
import gleam/int
import gleam/io
import gleam/json
import gleam/list
import gleam/option.{type Option, Some, None}
import gleam/regexp
import gleam/result
import gleam/string.{inspect as ins}
import gleam/crypto
import vxml/blame.{type Blame} as bl
import desugaring/core.{
  type Desugarer,
  type DesugaringError,
  type DesugaringWarning,
  type DesugarerTransform,
  Desugarer,
  DesugaringError,
  DesugaringWarning,
} as core
import desugaring/nodemaps_2_transform as n2t
import on
import shellout
import simplifile
import ansel/image
import desugaring/tables as pr
import either_or.{Either}
import filepath
import vxml.{
  type VXML,
  type Attr,
  Attr,
  V,
}

fn build_method_to_string(
  build_method: BuildMethod,
) -> String {
  case build_method {
    CP -> "cp"
    SVGO -> "svgo"
  }
}

fn build_img_info_prettified_json_string(
  key: String,
  info: BuildImgInfo,
  indent: Int,
  indentation: Int,
) -> String {
  let margin1 = string.repeat(" ", indent)
  let margin2 = string.repeat(" ", indent + indentation)
  margin1 <> "\"" <> key <> "\": {\n"
  <> margin2 <> "\"build-version\": " <> { json.string(info.build_version) |> json.to_string } <> ",\n"
  <> margin2 <> "\"build-version-created-on\": " <> { json.int(info.build_version_created_on) |> json.to_string } <> ",\n"
  <> margin2 <> "\"build-method\": " <> { json.string(info.build_method |> build_method_to_string) |> json.to_string } <> ",\n"
  <> margin2 <> "\"build-version-size\": " <> { json.int(info.build_version_size) |> json.to_string } <> ",\n"
  <> margin2 <> "\"original-size\": " <> { json.int(info.original_size) |> json.to_string } <> ",\n"
  <> margin2 <> "\"compressed-size\": " <> { json.int(info.compressed_size) |> json.to_string } <> ",\n"
  <> margin2 <> "\"compression\": " <> { json.string(info.compression) |> json.to_string } <> ",\n"
  <> margin2 <> "\"intrinsic-width\": " <> { json.string(info.intrinsic_width) |> json.to_string } <> ",\n"
  <> margin2 <> "\"intrinsic-height\": " <> { json.string(info.intrinsic_height) |> json.to_string } <> ",\n"
  <> margin2 <> "\"used-last-build\": " <> { json.bool(info.used_last_build) |> json.to_string } <> ",\n"
  <> margin2 <> "\"3chars\": " <> { json.array(info.three_chars, json.string) |> json.to_string } <> "\n"
  <> margin1 <> "}"
}

fn image_map_prettified_json_string(
  image_map: ImageMap,
  indentation: Int,
) -> String {
  let entries =
    image_map
    |> dict.to_list()
    |> list.map(fn(kv) { build_img_info_prettified_json_string(kv.0, kv.1, indentation, indentation) })
    |> string.join(",\n")
  "{\n" <> entries <> "\n}\n"
}

fn build_img_info_decoder() -> decode.Decoder(BuildImgInfo) {
  use build_version <- decode.field("build-version", decode.string)
  use build_version_created_on <- decode.field("build-version-created-on", decode.int)
  use build_method <- decode.field("build-method", decode.string)
  use build_version_size <- decode.field("build-version-size", decode.int)
  use original_size <- decode.field("original-size", decode.int)
  use compressed_size <- decode.field("compressed-size", decode.int)
  use compression <- decode.field("compression", decode.string)
  use intrinsic_width <- decode.optional_field("intrinsic-width", "", decode.string)
  use intrinsic_height <- decode.optional_field("intrinsic-height", "", decode.string)
  use _used_last_build <- decode.field("used-last-build", decode.bool)
  use _three_chars <- decode.optional_field("3chars", [], decode.list(decode.string))

  let #(success, build_method) = case build_method {
    "cp" -> #(True, CP)
    "svgo" -> #(True, SVGO)
    _ -> #(False, SVGO)
  }

  let decoded = BuildImgInfo(
    build_version: build_version,
    build_version_created_on: build_version_created_on,
    build_method: build_method,
    build_version_size: build_version_size,
    original_size: original_size,
    compressed_size: compressed_size,
    compression: compression,
    intrinsic_width: intrinsic_width,
    intrinsic_height: intrinsic_height,
    used_last_build: False,
    three_chars: [],
  )

  case success {
    True -> decode.success(decoded)
    False -> decode.failure(decoded, "build-method")
  }
}

fn image_map_decoder() -> decode.Decoder(ImageMap) {
  decode.dict(decode.string, build_img_info_decoder())
}

const whoami = "  " <> name

fn load_image_map(image_map_path: String) -> ImageMap {
  case simplifile.is_file(image_map_path) {
    Ok(True) -> {
      case simplifile.read(image_map_path) {
        Ok(content) -> {
          case json.parse(content, image_map_decoder()) {
            Ok(map) -> map
            Error(err) -> {
              io.println(whoami <> ": JSON cannot be parsed. Error: " <> string.inspect(err))
              io.println(whoami <> ": constructing new image map (1)")
              dict.new()
            }
          }
        }
        Error(err) -> {
          io.println(whoami <> ": '" <> image_map_path <> "' cannot be read (" <> simplifile.describe_error(err) <> ")")
          io.println(whoami <> ": constructing new image map (2)")
          dict.new()
        }
      }
    }
    _ -> {
      io.println(whoami <> ": '" <> image_map_path <> "' does not exist")
      io.println(whoami <> ": constructing new image map (3)")
      dict.new()
    }
  }
}

fn size_format(bytes: Int) -> String {
  case bytes > 500000 {
    False -> ins(bytes / 1000) <> "Kb"
    True -> {
      let mb = int.to_float(bytes) /. 1000000.0
      ins(mb |> float.to_precision(1)) <> "Mb"
    }
  }
}

fn sum_sizes(entries: List(BuildImgInfo)) -> #(Int, Int, Int) {
  case entries {
    [] -> #(0, 0, 0)
    [first, ..rest] -> {
      let #(a, b, c) = sum_sizes(rest)
      case first.used_last_build {
        True -> #(a + first.original_size, b + first.compressed_size, c + 1)
        False -> #(a, b, c)
      }
    }
  }
}

fn image_map_stats(image_map: ImageMap) -> Nil {
  let #(original_sizes, compressed_sizes, num) =
    image_map
    |> dict.values
    |> sum_sizes
  io.println("  lbp_img_build: " <> ins(num) <> " images")
  io.println("  lbp_img_build: original sizes: " <> size_format(original_sizes) <> ", compressed sizes: " <> size_format(compressed_sizes))
}

fn save_image_map(image_map: ImageMap, exec_to_image_map_path: String) -> Result(Nil, DesugaringError) {
  image_map_stats(image_map)
  let content = image_map_prettified_json_string(image_map, 2)
  case simplifile.read(exec_to_image_map_path) == Ok(content) {
    True -> Ok(Nil)
    False -> {
      use error <- on.error(simplifile.write(exec_to_image_map_path, content))
      Error(DesugaringError(bl.no_blame, "failed to save image map to '" <> exec_to_image_map_path <> "' (" <> simplifile.describe_error(error) <> ")"))
    }
  }
}

fn load_last_modified_time_entries(
  root: String,
  directory: String,
) -> Result(List(#(String, Int)), DesugaringError) {
  use names <- on.error_ok(simplifile.read_directory(directory), fn(error) {
    Error(DesugaringError(desugarer_blame(199), simplifile.describe_error(error)))
  })
  list.try_fold(names, [], fn(entries, name) {
    let path = filepath.join(directory, name)
    use info <- on.error_ok(simplifile.file_info(path), fn(error) {
      Error(DesugaringError(desugarer_blame(210), simplifile.describe_error(error)))
    })
    case simplifile.file_info_type(info) {
      simplifile.File -> Ok([#(core.assert_drop_prefix(path, root), info.mtime_seconds), ..entries])
      simplifile.Directory -> {
        use nested <- on.ok(load_last_modified_time_entries(root, path))
        Ok(list.append(nested, entries))
      }
      _ -> Ok(entries)
    }
  })
}

fn load_last_modified_times(exec_2_src_img: String) -> Result(LastModifiedTimes, DesugaringError) {
  use entries <- on.ok(load_last_modified_time_entries(exec_2_src_img, exec_2_src_img))
  Ok(dict.from_list(entries))
}

fn load_relative_file_set(directory: String) -> FileSet {
  case simplifile.get_files(directory) {
    Ok(paths) ->
      paths
      |> list.map(fn(path) { #(core.assert_drop_prefix(path, directory), Nil) })
      |> dict.from_list
    Error(_) -> dict.new()
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

fn hash_is_used(image_map: ImageMap, hash: String) -> Bool {
  image_map
  |> dict.values
  |> list.any(fn(info) {
    info.build_version
    |> string.split("/")
    |> list.last
    |> result.map(string.starts_with(_, hash))
    |> result.unwrap(False)
  })
}

fn get_hashed_filename(original_name: String, image_map: ImageMap) -> String {
  let big_string =
    original_name
    |> bit_array.from_string
    |> crypto.hash(crypto.Md5, _)
    |> bit_array.base64_url_encode(False)
  let s1 = string.slice(big_string, 0, 4)
  use <- on.eager_false_true(hash_is_used(image_map, s1), s1)
  let s2 = string.slice(big_string, 4, 8)
  use <- on.false_true(hash_is_used(image_map, s1 <> s2), fn() { s1 <> s2 })
  let s3 = string.slice(big_string, 8, 12)
  s1 <> s2 <> s3 // 64^(-12) = 2^{-72} seems pretty unlucky! let us know!
}

fn get_modified_date(path: String) -> Result(Int, simplifile.FileError) {
  use info <- result.try(simplifile.file_info(path))
  Ok(info.mtime_seconds)
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

type BuildMethod {
  SVGO
  CP
}

fn run_shellout(
  via: BuildMethod,
  exec_2_src_version: String,
  exec_2_build_version: String,
) -> Result(Nil, DesugaringError) {
  let cmd = case via {
    SVGO -> "svgo " <> exec_2_src_version <> " -o " <> exec_2_build_version
    CP -> "cp " <> exec_2_src_version <> " " <> exec_2_build_version
  }
  io.println(whoami <> ": " <> cmd)
  let result = case via {
    SVGO -> {
      shellout.command(
        run: "svgo",
        with: [exec_2_src_version, "-o", exec_2_build_version],
        in: ".",
        opt: [],
      )
    }
    CP -> {
      shellout.command(
        run: "cp",
        with: [exec_2_src_version, exec_2_build_version],
        in: ".",
        opt: [],
      )
    }
  }
  case result {
    Ok(_) -> Ok(Nil)
    Error(e) -> Error(DesugaringError(
      desugarer_blame(292),
      "failed to execute: '" <> cmd <> "' (error: " <> string.inspect(e) <> ")"
    ))
  }
}

fn create_dirs_on_path_to_file(path_to_file: String) -> Result(Nil, simplifile.FileError) {
  path_to_file
  |> string.split("/")
  |> core.drop_last()
  |> string.join("/")
  |> simplifile.create_directory_all
}

fn build_or_miraculously_retrieve_existing_build_image(
  via: BuildMethod,
  exec_2_src_version: String,
  exec_2_build_img: String,
  build_img_2_build_version: String,
  original_last_modified: Int,
) -> Result(BuildImgInfo, DesugaringError) {
  let exec_2_build_version = exec_2_build_img <> build_img_2_build_version
  let _ = create_dirs_on_path_to_file(exec_2_build_version)

  use _ <- on.ok(
    case {
      { simplifile.is_file(exec_2_build_version) == Ok(True) } &&
      { get_modified_date(exec_2_build_version) |> result.unwrap(-1) } > original_last_modified
    } {
      True -> {
        io.println(whoami <> ": found existing " <> {via |> build_method_to_string |> string.uppercase} <> "-build of " <> exec_2_src_version <> "; adding back to dictionary")
        Ok(Nil)
      }
      False -> run_shellout(via, exec_2_src_version, exec_2_build_version)
    }
  )

  use modified_date <- on.error_ok(
    get_modified_date(exec_2_build_version),
    fn(err) {
      Error(DesugaringError(
        desugarer_blame(333),
        "could not get created date of optimized image: " <> exec_2_build_version <> ": " <> simplifile.describe_error(err),
      ))
    }
  )

  use original_size <- on.error_ok(
    get_file_size(exec_2_src_version),
    fn(_) {
      Error(DesugaringError(
        desugarer_blame(343),
        "Could not get size of original image: " <> exec_2_src_version,
      ))
    }
  )

  use new_size <- on.error_ok(
    get_file_size(exec_2_build_version),
    fn(_) {
      Error(DesugaringError(
        desugarer_blame(353),
        "Could not get size of build image: " <> exec_2_build_version,
      ))
    }
  )

  let compression = compression_pct_string(original_size, new_size)

  BuildImgInfo(
    build_version: build_img_2_build_version,
    build_version_created_on: modified_date,
    build_method: via,
    build_version_size: new_size,
    original_size: original_size,
    compressed_size: new_size,
    compression: compression,
    intrinsic_width: "",
    intrinsic_height: "",
    used_last_build: True,
    three_chars: [],
  )
  |> Ok
}

fn update_src_attr(attrs: List(Attr), src: String) -> List(Attr) {
  core.attrs_set(attrs, desugarer_blame(376), "src", src)
}

fn first_regexp_submatch(pattern: regexp.Regexp, content: String) -> Option(String) {
  case regexp.scan(pattern, content) {
    [match, ..] -> case match.submatches {
      [Some(value), ..] -> Some(value)
      _ -> None
    }
    [] -> None
  }
}

fn first_two_regexp_submatches(pattern: regexp.Regexp, content: String) -> Option(#(String, String)) {
  case regexp.scan(pattern, content) {
    [match, ..] -> case match.submatches {
      [Some(first), Some(second), ..] -> Some(#(first, second))
      _ -> None
    }
    [] -> None
  }
}

fn svg_intrinsic_dimensions(blame: Blame, path: String, patterns: SvgPatterns) -> Result(#(String, String), DesugaringError) {
  use content <- on.error_ok(
    simplifile.read(path),
    fn(error) { Error(DesugaringError(blame, "could not read image dimensions from '" <> path <> "' (" <> simplifile.describe_error(error) <> ")")) },
  )
  use svg_tag <- on.none_some(
    first_regexp_submatch(patterns.svg, content),
    fn() { Error(DesugaringError(blame, "could not find root svg element in '" <> path <> "'")) },
  )

  let width = first_regexp_submatch(patterns.width, svg_tag)
  let height = first_regexp_submatch(patterns.height, svg_tag)
  case width, height {
    Some(width), Some(height) -> Ok(#(width, height))
    _, _ -> {
      use dimensions <- on.none_some(
        first_two_regexp_submatches(patterns.viewbox, svg_tag),
        fn() { Error(DesugaringError(blame, "could not determine intrinsic dimensions of '" <> path <> "'")) },
      )
      Ok(dimensions)
    }
  }
}

fn intrinsic_dimensions(blame: Blame, path: String, patterns: SvgPatterns) -> Result(#(String, String), DesugaringError) {
  case string.ends_with(string.lowercase(path), ".svg") {
    True -> svg_intrinsic_dimensions(blame, path, patterns)
    False -> case image.read(path) {
      Ok(bitmap) -> Ok(#(
        image.get_width(bitmap) |> int.to_string,
        image.get_height(bitmap) |> int.to_string,
      ))
      Error(error) -> Error(DesugaringError(blame, "could not determine intrinsic dimensions of '" <> path <> "': " <> ins(error)))
    }
  }
}

fn add_intrinsic_dimensions(
  attrs: List(Attr),
  src: String,
  src_attr: Attr,
  inner: InnerParam,
) -> Result(List(Attr), DesugaringError) {
  let path = case src {
    "tmp-images/" <> _ -> inner.exec_2_build <> src
    _ -> inner.exec_2_src <> src
  }
  use <- on.false_true(simplifile.is_file(path) == Ok(True), fn() { Ok(attrs) })
  use dimensions <- on.ok(intrinsic_dimensions(src_attr.blame, path, inner.svg_patterns))
  let attrs = core.attrs_set(attrs, desugarer_blame(450), "intrinsicWidth", dimensions.0)
  Ok(core.attrs_set(attrs, desugarer_blame(451), "intrinsicHeight", dimensions.1))
}

fn add_cached_intrinsic_dimensions(attrs: List(Attr), info: BuildImgInfo) -> List(Attr) {
  attrs
  |> core.attrs_set(desugarer_blame(462), "intrinsicWidth", info.intrinsic_width)
  |> core.attrs_set(desugarer_blame(463), "intrinsicHeight", info.intrinsic_height)
}

fn ensure_intrinsic_dimensions(
  info: BuildImgInfo,
  src_attr: Attr,
  path: String,
  inner: InnerParam,
) -> Result(BuildImgInfo, DesugaringError) {
  case info.intrinsic_width != "" && info.intrinsic_height != "" {
    True -> Ok(info)
    False -> {
      use dimensions <- on.ok(intrinsic_dimensions(src_attr.blame, path, inner.svg_patterns))
      Ok(BuildImgInfo(..info, intrinsic_width: dimensions.0, intrinsic_height: dimensions.1))
    }
  }
}

fn v_before(
  vxml: VXML,
  image_map: ImageMap,
  inner: InnerParam,
) -> Result(#(VXML, ImageMap, List(DesugaringWarning)), DesugaringError) {
  let assert V(_, tag, attrs, _) = vxml

  // escape #1: no 'src' expected:
  use <- on.false_true(
    list.contains(img_tags, tag),
    fn() { Ok(#(vxml, image_map, [])) },
  )

  use #(svgo_attr, attrs) <- on.ok(
    core.attrs_extract_unique_key_or_none(attrs, "svgo"),
  )

  let vxml = V(..vxml, attrs: attrs)

  // escape #2: 'src' missing:
  use src_attr <- on.none_some(
    core.attrs_first_with_key(attrs, "src"),
    fn() { Ok(#(vxml, image_map, [])) },
  )

  let src = src_attr.val |> core.drop_prefix("./") |> core.drop_prefix("/")

  // escape #3: src does not start with the expected src_2_src_img prefix
  use <- on.false_true(
    string.starts_with(src, inner.src_2_src_img),
    fn() {
      use attrs <- on.ok(add_intrinsic_dimensions(attrs, src, src_attr, inner))
      Ok(#(V(..vxml, attrs: attrs), image_map, []))
    },
  )

  let src_img_2_src_version = src |> string.drop_start(inner.src_2_src_img_length)

  // escape #4: the source file does not exist; we escape,
  // but generate a warning
  use last_modified <- on.error_ok(
    dict.get(inner.src_img_mod_times, src_img_2_src_version),
    fn(_) {
      Ok(#(
        vxml,
        image_map,
        [DesugaringWarning(src_attr.blame, "file not found: " <> src_attr.val)],
      ))
    },
  )

  use extension <- on.ok(img_extension(src, src_attr.blame))

  let three_chars_val = case src_attr.blame {
    bl.Src(_, path, _, _, _) -> string.slice(path, 0, 3)
    _ -> "---"
  }

  let svgo_suppressed = case svgo_attr {
    Some(Attr(_, _, "false")) -> True
    _ -> False
  }

  let cmd = case extension != "svg" || svgo_suppressed || inner.quick_mode {
    True -> CP
    False -> SVGO
  }

  let up_to_date_img_info = {
    use img_info <- on.error_ok(
      dict.get(image_map, src_img_2_src_version),
      fn(_) { None },
    )
    use <- on.eager_true_false(
      last_modified > img_info.build_version_created_on,
      None,
    )
    use <- on.eager_true_false(
      cmd == SVGO && img_info.build_method != cmd && !inner.quick_mode,
      None,
    )
    use <- on.true_false(
      img_info.used_last_build || dict.has_key(inner.build_img_files, img_info.build_version),
      fn() { Some(img_info) },
    )
    io.println(whoami <> ": " <> img_info.build_version <> " missing from " <> inner.exec_2_build_img <> " (!!)")
    None
  }

  // escape #5: there exists an 'up_to_date_img_info'
  use <- on.some_none(
    up_to_date_img_info,
    fn (up_to_date_img_info) {
      use up_to_date_img_info <- on.ok(ensure_intrinsic_dimensions(up_to_date_img_info, src_attr, inner.exec_2_src_img <> src_img_2_src_version, inner))
      let attrs =
        attrs
        |> add_cached_intrinsic_dimensions(up_to_date_img_info)
        |> update_src_attr("/" <> inner.build_2_build_img <> up_to_date_img_info.build_version)
      let up_to_date_img_info =
        BuildImgInfo(
          ..up_to_date_img_info,
          used_last_build: True,
          three_chars: list.append(up_to_date_img_info.three_chars, [three_chars_val]),
        )
      let image_map = dict.insert(image_map, src_img_2_src_version, up_to_date_img_info)
      Ok(#(V(..vxml, attrs: attrs), image_map, []))
    }
  )

  let build_img_2_build_version = case cmd {
    CP -> extension <> "/" <> get_hashed_filename(src_img_2_src_version, image_map) <> "." <> extension
    SVGO -> "svgo-svg" <> "/" <> get_hashed_filename(src_img_2_src_version, image_map) <> "." <> extension
  }

  use img_info <- on.ok(build_or_miraculously_retrieve_existing_build_image(
    cmd,
    inner.exec_2_src_img <> src_img_2_src_version,
    inner.exec_2_build_img,
    build_img_2_build_version,
    last_modified,
  ))

  use img_info <- on.ok(ensure_intrinsic_dimensions(img_info, src_attr, inner.exec_2_src_img <> src_img_2_src_version, inner))

  let attrs =
    attrs
    |> add_cached_intrinsic_dimensions(img_info)
    |> update_src_attr("/" <> inner.build_2_build_img <> img_info.build_version)

  let img_info =
    BuildImgInfo(..img_info, three_chars: list.append(img_info.three_chars, [three_chars_val]))
  let image_map = dict.insert(image_map, src_img_2_src_version, img_info)

  Ok(#(V(..vxml, attrs: attrs), image_map, []))
}

fn remove_files_from_build_img_that_have_no_image_map_preimage(
  state: ImageMap,
  inner: InnerParam,
) -> Result(Nil, DesugaringError) {
  use paths <- on.error_ok(
    simplifile.get_files(inner.exec_2_build_img),
    fn(err) { Error(DesugaringError(desugarer_blame(587), "could not read build_img files at "  <> inner.exec_2_build_img <> " for cleanup: "  <> simplifile.describe_error(err))) }
  )
  let build_versions =
    state
    |> dict.values
    |> list.map(fn(info) { #(info.build_version, Nil) })
    |> dict.from_list
  list.each(
    paths,
    fn (path) {
      let key = path |> core.assert_drop_prefix(inner.exec_2_build_img)
      case dict.has_key(build_versions, key) {
        True -> Nil
        False -> {
          io.println(whoami <> ": rm " <> path)
          let _ = shellout.command(
            run: "rm",
            with: [path],
            in: ".",
            opt: [],
          )
          Nil
        }
      }
    }
  )
  |> Ok
}

fn v_after(
  vxml: VXML,
  ancestors: List(VXML),
  state: ImageMap,
  inner: InnerParam,
) -> Result(#(VXML, ImageMap, List(DesugaringWarning)), DesugaringError) {
  case ancestors {
    [] -> {
      let state = case inner.cleanup_image_map {
        True -> {
          dict.filter(state, fn(k, v) {
            case v.used_last_build {
              True -> True
              False -> {
                io.println(whoami <> ": removing '" <> k <> "' from image_map")
                False
              }
            }
          })
        }
        False -> state
      }
      use _ <- on.ok(case inner.cleanup_build_img {
        False -> Ok(Nil)
        True -> remove_files_from_build_img_that_have_no_image_map_preimage(state, inner)
      })
      use _ <- on.ok(save_image_map(state, inner.image_map_path))

      let table_rows =
        state
        |> dict.to_list()
        |> list.filter(fn(kv) {
          kv.1.used_last_build && kv.1.compressed_size >= 200_000
        })
        |> list.sort(fn(a, b) { int.compare(b.1.compressed_size, a.1.compressed_size) })
        |> list.map(fn(kv) {
          let #(path, info) = kv
          #(path, size_format(info.original_size), size_format(info.compressed_size))
        })

      case table_rows {
        [] -> Nil
        _ -> {
          io.println("  lbp_img_build image report:")
          pr.three_column_table(
            [Either(#("Original path", "Original size", "Compressed size")),
             ..list.map(table_rows, Either)]
          )
          |> pr.print_lines_at_indent(2)
        }
      }

      Ok(#(vxml, state, []))
    }
    _ -> Ok(#(vxml, state, []))
  }
}

fn nodemap_factory(
  inner: InnerParam,
) -> n2t.FancyOneToOneBeforeAndAfterStatefulNodemapWithWarnings(State) {
   n2t.FancyOneToOneBeforeAndAfterStatefulNodemapWithWarnings(
    v_before_transforming_children: fn(vxml, _, _, _, _, state) {
      v_before(vxml, state, inner)
    },
    v_after_transforming_children: fn(vxml, ancestors, _, _, _, _, latest_state) {
      v_after(vxml, ancestors, latest_state, inner)
    },
    t_nodemap: fn(vxml, _, _, _, _, state) {
      Ok(#(vxml, state, []))
    },
  )
}

fn transform_factory(inner: InnerParam) -> DesugarerTransform {
  let image_map = load_image_map(inner.image_map_path)
  nodemap_factory(inner)
  |> n2t.fancy_one_to_one_before_and_after_stateful_nodemap_with_warnings_2_desugarer_transform(image_map)
}

fn ensure_suffix_if_nonempty(s: String, t: String) -> String {
  case s {
    "" -> ""
    _ -> s |> core.ensure_suffix(t)
  }
}

fn compile_svg_patterns() -> SvgPatterns {
  let assert Ok(svg) = regexp.from_string("(<svg[^>]*>)")
  let assert Ok(width) = regexp.from_string("(?:^|[[:space:]])width=['\"]([0-9]+(?:\\.[0-9]+)?)(?:[a-zA-Z%]*)['\"]")
  let assert Ok(height) = regexp.from_string("(?:^|[[:space:]])height=['\"]([0-9]+(?:\\.[0-9]+)?)(?:[a-zA-Z%]*)['\"]")
  let assert Ok(viewbox) = regexp.from_string("(?:^|[[:space:]])viewBox=['\"][[:space:]]*[-+0-9.]+[[:space:],]+[-+0-9.]+[[:space:],]+([0-9]+(?:\\.[0-9]+)?)[[:space:],]+([0-9]+(?:\\.[0-9]+)?)['\"]")
  SvgPatterns(svg, width, height, viewbox)
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  assert param.0 != ""
  assert param.1 != ""
  assert !string.starts_with(param.2, "/")
  assert !string.starts_with(param.2, "./")
  assert !string.starts_with(param.2, "../")
  assert !string.starts_with(param.3, "/")
  assert !string.starts_with(param.3, "./")
  assert !string.starts_with(param.3, "../")

  let exec_2_src = param.0 |> core.ensure_suffix("/")
  let exec_2_build = param.1 |> core.ensure_suffix("/")
  let src_2_src_img = param.2 |> ensure_suffix_if_nonempty("/")
  let build_2_build_img = param.3 |> ensure_suffix_if_nonempty("/")
  let exec_2_src_img = exec_2_src <> src_2_src_img
  let exec_2_build_img = exec_2_build <> build_2_build_img
  let src_2_src_img_length = src_2_src_img |> string.length()
  let build_img_files = load_relative_file_set(exec_2_build_img)

  use src_img_mod_times <- on.ok(load_last_modified_times(exec_2_src_img))

  InnerParam(
    exec_2_src: exec_2_src,
    exec_2_src_img: exec_2_src_img,
    exec_2_build: exec_2_build,
    exec_2_build_img: exec_2_build_img,
    src_2_src_img: src_2_src_img,
    src_2_src_img_length: src_2_src_img_length,
    build_2_build_img: build_2_build_img,
    image_map_path: param.4,
    src_img_mod_times: src_img_mod_times,
    build_img_files: build_img_files,
    cleanup_image_map: param.5,
    cleanup_build_img: param.6,
    quick_mode: param.7,
    svg_patterns: compile_svg_patterns(),
  )
  |> Ok
}

const img_tags = ["img", "Image", "ImageLeft", "ImageRight", "InlineImage"]
const supported_extensions = ["svg", "png", "jpg", "jpeg", "gif", "webp"]

type BuildImgInfo {
  BuildImgInfo(
    build_version: String,
    build_version_created_on: Int,
    build_method: BuildMethod,
    build_version_size: Int,
    original_size: Int,
    compressed_size: Int,
    compression: String, // e.g. "38.85%"
    intrinsic_width: String,
    intrinsic_height: String,
    used_last_build: Bool,
    three_chars: List(String),
  )
}

type ImageMap = Dict(String, BuildImgInfo)
type LastModifiedTimes = Dict(String, Int) // path -> last_modified timestamp
type FileSet = Dict(String, Nil)
type State = ImageMap

type SvgPatterns {
  SvgPatterns(svg: regexp.Regexp, width: regexp.Regexp, height: regexp.Regexp, viewbox: regexp.Regexp)
}

type Param = #(
  // **********************************************************
  // on the following semantics, please note:
  //
  //  - 'src' means the directory that author mentally
  //    uses as the root folder for 'src' attributes
  //  - 'src_img' is the subfolder of src
  //    that contains images that are to be processed
  //    by this image pipeline
  //
  // for example, if 'src' attributes have the form
  //
  //    src=imgs/ch2/something.svg
  //
  // and the 'imgs' directory sit inside of '../assets'
  // relative to the executable, and where 'imgs' directory
  // is the director that contains images that are meant to be
  // processed by this (the standard) pipeline, then we would
  // have
  //
  //    exec_2_src = "../assets/"   (callers can skip the trailing backlash, it will be added automatically the desugarer)
  //    src_2_src_img = "imgs/"     (ditto)
  //
  // Also:
  //
  //  - 'build' is the build directory
  //  - 'build_img' is the subdirectory of build meant
  //    to contain the build version of images produced
  //    by this pipeline
  //  - image-map.json contains a dictionary whose keys
  //    are paths relative to src_img; the 'build_version'
  //    field of each item is a path relative to build_img
  //    directory
  // **********************************************************
  String,           // exec_2_src
  String,           // exec_2_build
  String,           // src_2_src_img
  String,           // build_2_build_img
  String,           // location of image_map.json relative to exec
  Bool,             // remove unused entries from image_map
  Bool,             // remove unused files in build_img
  Bool,             // 'quick mode': build with cp instead of svgo
)

type InnerParam {
  InnerParam(
    exec_2_src: String,
    exec_2_src_img: String,
    exec_2_build: String,
    exec_2_build_img: String,
    src_2_src_img: String,
    src_2_src_img_length: Int,
    build_2_build_img: String,
    image_map_path: String,
    src_img_mod_times: LastModifiedTimes,
    build_img_files: FileSet,
    cleanup_image_map: Bool,
    cleanup_build_img: Bool,
    quick_mode: Bool,
    svg_patterns: SvgPatterns,
  )
}

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

fn assertive_tests_data() -> List(core.AssertiveTestData(Param)) {
  []
}

pub fn assertive_tests() {
  core.assertive_test_collection_from_data(name, assertive_tests_data(), constructor)
}
