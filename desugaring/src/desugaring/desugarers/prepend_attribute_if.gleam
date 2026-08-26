import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
  type TrafficLight, Continue,
}
import desugaring/nodemaps_2_transform as n2t
import vxml.{type Attr, type VXML, Attr, V}

pub const name = "prepend_attribute_if"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Prepends an attribute when a matching element satisfies
/// the configured condition.
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
    // Target tag.
    String,
    // Condition applied to the target.
    fn(VXML) -> Bool,
    // Attribute key.
    String,
    // Attribute value.
    String,
    // Whether to return early after finding a target.
    TrafficLight,
  )

type InnerParam =
  #(String, fn(VXML) -> Bool, Attr, TrafficLight)

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  #(param.0, param.1, Attr(desugarer_blame(44), param.2, param.3), param.4)
  |> Ok
}

fn inner_param_to_transform(inner: InnerParam) -> DesugarerTransform {
  nodemap_factory(inner)
  |> n2t.early_return_one_to_one_no_error_nodemap_2_desugarer_transform
}

fn nodemap_factory(inner: InnerParam) -> n2t.EarlyReturnOneToOneNoErrorNodemap {
  nodemap(_, inner)
}

fn nodemap(vxml: VXML, inner: InnerParam) -> #(VXML, TrafficLight) {
  case vxml {
    V(_, tag, attrs, _) if tag == inner.0 -> {
      case inner.1(vxml) {
        True -> #(V(..vxml, attrs: [inner.2, ..attrs]), inner.3)
        False -> #(vxml, Continue)
      }
    }
    _ -> #(vxml, Continue)
  }
}

fn desugarer_blame(line_no: Int) {
  authoring.blame(name, line_no)
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊

fn assertive_tests_data() -> List(core.AssertiveTestData(Param)) {
  [
    core.AssertiveTestData(
      param: #(
        "section",
        core.v_has_key_val(_, "enabled", "yes"),
        "new",
        "first",
        Continue,
      ),
      source: "
                <> root
                  <> section
                    enabled=yes
                    old=second
                  <> section
                    enabled=no
                  <> aside
                    enabled=yes
                ",
      expected: "
                <> root
                  <> section
                    new=first
                    enabled=yes
                    old=second
                  <> section
                    enabled=no
                  <> aside
                    enabled=yes
                ",
    ),
  ]
}

pub fn assertive_tests() {
  core.assertive_test_collection_from_data(
    name,
    assertive_tests_data(),
    constructor,
  )
}
