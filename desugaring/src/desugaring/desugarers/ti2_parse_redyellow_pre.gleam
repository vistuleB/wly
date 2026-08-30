import desugaring/authoring
import desugaring/core.{type Desugarer, type DesugarerTransform}
import desugaring/nodemaps_2_transform as n2t
import vxml.{type VXML, V}
import vxml/blame as bl

pub const name = "ti2_parse_redyellow_pre"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Converts `language=redyellow` on pre elements into the
/// corresponding CSS class.
pub fn constructor() -> Desugarer {
  authoring.no_param_desugarer(
    name: name,
    transform: inner_param_to_transform(),
  )
}

fn inner_param_to_transform() -> DesugarerTransform {
  let nodemap: n2t.OneToOneNoErrorNodemap = nodemap
  nodemap
  |> n2t.one_to_one_no_error_nodemap_2_desugarer_transform
}

fn nodemap(vxml: VXML) -> VXML {
  case vxml {
    V(_, "pre", attrs, _) -> {
      case core.v_has_key_val(vxml, "language", "redyellow") {
        True ->
          V(
            ..vxml,
            attrs: attrs
              |> core.attrs_delete("language")
              |> core.attrs_append_classes(desugarer_blame(31), "redyellow"),
          )
        _ -> vxml
      }
    }
    _ -> vxml
  }
}

fn desugarer_blame(line_no: Int) {
  bl.Des([], name, line_no)
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
fn assertive_tests_data() -> List(core.AssertiveTestDataNoParam) {
  [
    core.AssertiveTestDataNoParam(
      source: "
                          <> root
                            <> pre
                              language=redyellow
                              class=listing
                              <>
                                'some code here'
                                'with multiple lines'
                ",
      expected: "
                          <> root
                            <> pre
                              class=listing redyellow
                              <>
                                'some code here'
                                'with multiple lines'
                ",
    ),
    core.AssertiveTestDataNoParam(
      source: "
                          <> root
                            <> pre
                              language=redyellow
                              <>
                                'just redyellow code'
                ",
      expected: "
                          <> root
                            <> pre
                              class=redyellow
                              <>
                                'just redyellow code'
                ",
    ),
    core.AssertiveTestDataNoParam(
      source: "
                          <> root
                            <> pre
                              language=other
                              <>
                                'should not change'
                ",
      expected: "
                          <> root
                            <> pre
                              language=other
                              <>
                                'should not change'
                ",
    ),
  ]
}

pub fn assertive_tests() {
  core.assertive_test_collection_from_data_no_param(
    name,
    assertive_tests_data(),
    constructor,
  )
}
