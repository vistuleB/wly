import desugaring/core.{type Desugarer, type Pipeline}
import desugaring/desugarers as dl
import desugaring/pipelines as pp
import gleam/list
import vxml.{type VXML, V}

fn apply_pipeline(vxml: VXML, pipeline: Pipeline) -> VXML {
  list.fold(pipeline, vxml, fn(vxml, desugarer: Desugarer) {
    let assert Ok(#(vxml, _warnings)) = desugarer.transform(vxml)
    vxml
  })
}

fn contains_annotated_span(vxml: VXML) -> Bool {
  case vxml {
    V(_, "span", attrs, children) ->
      case
        core.attrs_have_class(attrs, "manual-color")
        && core.descendant_text_contains(vxml, "marked")
      {
        True -> True
        False -> list.any(children, contains_annotated_span)
      }
    V(_, _, _, children) -> list.any(children, contains_annotated_span)
    _ -> False
  }
}

fn assert_annotation_survives(source: String, colorer: Desugarer) {
  let assert Ok([vxml]) = vxml.parse_string(source, "integration test", True)
  let pipeline = [
    colorer,
    ..pp.annotated_backtick_splitting("span", "class", ["WriterlyBlankLine"], [
      "MathBlock",
      "Math",
    ])
  ]
  let output = apply_pipeline(vxml, pipeline)
  assert contains_annotated_span(output)
}

pub fn dominik_prompt_response_preserves_annotations_test() {
  assert_annotation_survives(
    "<> pre
  language=dominik-prompt-response
  <>
    '$ echo `marked`{manual-color}'",
    dl.ti2_dominik_prompt_response(),
  )
}

pub fn python_prompt_preserves_annotations_test() {
  assert_annotation_survives(
    "<> pre
  language=python-prompt
  <>
    '>>> print(`marked`{manual-color})'",
    dl.ti2_parse_python_prompt_pre(),
  )
}

pub fn arbitrary_prompt_response_preserves_annotations_test() {
  assert_annotation_survives(
    "<> pre
  language=arbitrary-prompt-response
  <>
    'Result: <- `marked`{manual-color}'",
    dl.ti2_parse_arbitrary_prompt_response_pre(),
  )
}

pub fn orange_comments_preserves_annotations_test() {
  assert_annotation_survives(
    "<> pre
  language=orange-comments
  <>
    'value // `marked`{manual-color}'",
    dl.ti2_parse_orange_comments_pre(),
  )
}

pub fn xml_preserves_annotations_test() {
  assert_annotation_survives(
    "<> pre
  language=xml
  <>
    '<p>`marked`{manual-color}</p>'",
    dl.ti2_parse_xml_pre(),
  )
}

pub fn redyellow_preserves_annotations_test() {
  assert_annotation_survives(
    "<> pre
  language=redyellow
  <>
    '`marked`{manual-color}'",
    dl.ti2_parse_redyellow_pre(),
  )
}

pub fn listing_bol_spans_preserve_annotations_test() {
  assert_annotation_survives(
    "<> pre
  class=listing
  <>
    'first line'
    '`marked`{manual-color}'",
    dl.ti2_add_listing_bol_spans(),
  )
}

pub fn main() {
  dominik_prompt_response_preserves_annotations_test()
  python_prompt_preserves_annotations_test()
  arbitrary_prompt_response_preserves_annotations_test()
  orange_comments_preserves_annotations_test()
  xml_preserves_annotations_test()
  redyellow_preserves_annotations_test()
  listing_bol_spans_preserve_annotations_test()
}
