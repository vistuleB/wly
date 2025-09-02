import gleam/dict.{type Dict}
import gleam/list
import gleam/option
import infrastructure.{type Desugarer, Desugarer, type DesugarerTransform, type DesugaringError} as infra
import nodemaps_2_desugarer_transforms as n2t
import vxml.{type VXML, Attribute, V}
import on

fn nodemap(
  vxml: VXML,
  ancestors: List(VXML),
  inner: InnerParam,
) -> VXML {
  use blame, tag, attributes, children <- infra.on_t_on_v(
    vxml,
    fn(_, _) {vxml}
  )

  use parent, _ <- on.lazy_empty_nonempty(ancestors, fn() { vxml })

  let assert V(_, parent_tag, _, _) = parent

  use attributes_to_add <- on.error_ok(
    dict.get(inner, #(tag, parent_tag)),
    fn(_) { vxml }
  )

  let old_attribute_keys = infra.keys(attributes)

  let attributes_to_add =
    list.fold(
      over: attributes_to_add,
      from: [],
      with: fn(so_far, pair) {
        let #(key, value) = pair
        case list.contains(old_attribute_keys, key) {
          True -> so_far
          False -> [Attribute(blame, key, value), ..so_far]
        }
      }
    )
    |> list.reverse

  V(blame, tag, list.append(attributes, attributes_to_add), children)
}

fn nodemap_factory(inner: InnerParam) -> n2t.FancyOneToOneNoErrorNodeMap {
  fn(vxml, ancestors, _, _, _) { nodemap(vxml, ancestors, inner) }
}

fn transform_factory(inner: InnerParam) -> DesugarerTransform {
  nodemap_factory(inner)
  |> n2t.fancy_one_to_one_no_error_nodemap_2_desugarer_transform()
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  param
  |> infra.quads_to_pair_pairs
  |> infra.aggregate_on_first
  |> Ok
}

type Param = List(#(String, String, String, String))
//                  ↖       ↖       ↖       ↖
//                  tag     parent  attr    value
type InnerParam = Dict(#(String, String), List(#(String, String)))

pub const name = "append_attribute_if_child_of__batch"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// adds an attribute-pair to a tag when it is the
/// child of another specified tag; will not
/// overwrite if attribute with that key already
/// exists
pub fn constructor(param: Param) -> Desugarer {
  Desugarer(
    name: name,
    stringified_param: option.Some(param |> infra.list_param_stringifier),
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
  [
    infra.AssertiveTestData(
      param: [#("B", "parent", "key1", "val1")],
      source:   "
                <> root
                  <> B
                    <> parent
                  <> parent
                    <> B
                  <> parent
                    <> B
                      key1=val2
                ",
      expected: "
                <> root
                  <> B
                    <> parent
                  <> parent
                    <> B
                      key1=val1
                  <> parent
                    <> B
                      key1=val2
                "
    )
  ]
}

pub fn assertive_tests() {
  infra.assertive_test_collection_from_data(name, assertive_tests_data(), constructor)
}
