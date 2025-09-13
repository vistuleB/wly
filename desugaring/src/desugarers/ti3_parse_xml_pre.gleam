import gleam/option
import gleam/string
import gleam/list
import infrastructure.{type Desugarer, Desugarer, type DesugarerTransform, type DesugaringError} as infra
import nodemaps_2_desugarer_transforms as n2t
import vxml.{type VXML, V, T, Attribute, TextLine}
import xml_streamer as xs
import blame.{type Blame} as bl

const newline_t =
  T(
    bl.Des([], name, 11),
    [
      TextLine(bl.Des([], name, 13), ""),
      TextLine(bl.Des([], name, 14), ""),
    ]
  )

fn span(blame: Blame, class: String, content: String) -> VXML {
  V(
    blame,
    "span",
    [Attribute(desugarer_blame(23), "class", class)],
    [T(blame, [TextLine(blame, content)])],
  )
}

fn nodemap(
  vxml: VXML,
) -> VXML {
  case vxml {
    V(_, "pre", attributes, children) -> {
      case infra.v_has_key_value(vxml, "language", "xml") || infra.v_has_key_value(vxml, "language", "html") {
        True -> {
          let attributes =
            attributes
            |> infra.attributes_delete("language")
            |> infra.append_to_class_attribute(desugarer_blame(38), "html")
          let children =
            children
            |> list.flat_map(fn(x) {
              case x {
                V(_, _, _, _) -> [x]
                T(_, lines) -> {
                  let pairs = list.map(lines, fn(l) { #(l.blame, l.content) })
                  let events = xs.pairs_streamer(pairs)
                  list.flat_map(
                    events,
                    fn(event) {
                      case event {
                        xs.Newline(_) ->
                          [newline_t]
                        xs.TagStartOrdinary(b, tag) ->
                          [span(b, "xml-0", "<"), span(b, "xml-1", tag)]
                        xs.TagStartXMLVersion(b, tag) ->
                          [span(b, "xml-0", "<?"), span(b, "xml-1", tag)]
                        xs.TagStartDoctype(b, tag) ->
                          [span(b, "xml-0", "<!"), span(b, "xml-1", tag)]
                        xs.TagStartClosing(b, tag) ->
                          [span(b, "xml-0", "</"), span(b, "xml-1", tag)]
                        xs.InTagWhitespace(b, load) -> {
                          assert !string.contains(load, "\n")
                          assert !string.contains(load, "\r")
                          [T(b, [TextLine(b, load)])]
                        }
                        xs.Key(b, load) ->
                          [span(b, "xml-2", load)]
                        xs.KeyMalformed(b, load) ->
                          [span(b, "xml-2b", load)]
                        xs.Assignment(b) ->
                          [span(b, "xml-3", "=")]
                        xs.ValueDoubleQuoted(b, load) ->
                          [span(b, "xml-4", "\"" <> load <> "\"")]
                        xs.ValueSingleQuoted(b, load) ->
                          [span(b, "xml-4", "'" <> load <> "'")]
                        xs.ValueMalformed(b, load) ->
                          [span(b, "xml-4b", load)]
                        xs.TagEndOrdinary(b) ->
                          [span(b, "xml-0", ">")]
                        xs.TagEndXMLVersion(b) ->
                          [span(b, "xml-0", "?>")]
                        xs.TagEndSelfClosing(b) ->
                          [span(b, "xml-0", "/>")]
                        xs.Text(b, content) ->
                          [span(b, "xml-5", content)]
                        xs.CommentStartSequence(b) ->
                          [span(b, "xml-6", "<!--")]
                        xs.CommentEndSequence(b) ->
                          [span(b, "xml-6", "-->")]
                        xs.CommentContents(b, load) ->
                          [span(b, "xml-6", load)]
                      }
                    }
                  )
                }
              }
            })
          V(..vxml, attributes: attributes, children: children)
        }
        _ -> vxml
      }
    }
    _ -> vxml
  }
}

fn nodemap_factory(_inner: InnerParam) -> n2t.OneToOneNoErrorNodeMap {
  nodemap
}

fn transform_factory(inner: InnerParam) -> DesugarerTransform {
  nodemap_factory(inner)
  |> n2t.one_to_one_no_error_nodemap_2_desugarer_transform
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(param)
}

pub const name = "ti3_parse_xml_pre"
fn desugarer_blame(line_no: Int) { bl.Des([], name, line_no) }

type Param = Nil
type InnerParam = Param

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// Processes CodeBlock elements with
/// language=python-prompt and converts them to pre
/// elements with proper span highlighting for
/// prompts, responses, and errors
pub fn constructor() -> Desugarer {
  Desugarer(
    name: name,
    stringified_param: option.None,
    stringified_outside: option.None,
    transform: case param_to_inner_param(Nil) {
      Error(e) -> fn(_) { Error(e) }
      Ok(inner) -> transform_factory(inner)
    },
  )
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
fn assertive_tests_data() -> List(infra.AssertiveTestDataNoParam) {
  []
}

pub fn assertive_tests() {
  infra.assertive_test_collection_from_data_no_param(name, assertive_tests_data(), constructor)
}
