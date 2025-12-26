import gleam/option
import infrastructure.{type Desugarer, Desugarer, type DesugarerTransform, type DesugaringError} as infra
import nodemaps_2_desugarer_transforms as n2t
import vxml.{type VXML, V}
import blame as bl

fn nodemap(
  vxml: VXML,
) -> VXML {
  case vxml {
    V(_, "pre", attrs, _) -> {
      case infra.v_has_key_val(vxml, "language", "redyellow") {
        True ->
          V(
            ..vxml,
            attrs:
              attrs
              |> infra.attrs_delete("language")
              |> infra.attrs_append_classes(desugarer_blame(19), "redyellow"),
          )
        _ -> vxml
      }
    }
    _ -> vxml
  }
}

fn nodemap_factory(_inner: InnerParam) -> n2t.OneToOneNoErrorNodemap {
  nodemap
}

fn transform_factory(inner: InnerParam) -> DesugarerTransform {
  nodemap_factory(inner)
  |> n2t.one_to_one_no_error_nodemap_2_desugarer_transform
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(param)
}

pub const name = "ti2_parse_redyellow_pre"
fn desugarer_blame(line_no: Int) { bl.Des([], name, line_no) }

type Param = Nil
type InnerParam = Param

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// converts pre elements with language=redyellow to use
/// redyellow CSS class instead of language attr.
///
/// removes the language attr and adds "redyellow"
/// to the element's CSS classes for proper styling.
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
  [
    infra.AssertiveTestDataNoParam(
      source:   "
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
    infra.AssertiveTestDataNoParam(
      source:   "
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
    infra.AssertiveTestDataNoParam(
      source:   "
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
  infra.assertive_test_collection_from_data_no_param(name, assertive_tests_data(), constructor)
}
