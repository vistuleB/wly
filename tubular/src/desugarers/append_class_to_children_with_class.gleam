import gleam/dict.{type Dict}
import gleam/option
import gleam/string.{inspect as ins}
import infrastructure.{type Desugarer, Desugarer, type DesugarerTransform, type DesugaringError} as infra
import nodemaps_2_desugarer_transforms as n2t
import vxml.{type VXML, T, V}
import gleam/list

fn update_child(
  node: VXML,
  targets_and_classes_to_append: List(#(String, String)),
) -> VXML {
  list.fold(
    targets_and_classes_to_append,
    node,
    fn(acc, target_and_classes_to_append) {
      infra.v_append_classes_if(
        acc,
        target_and_classes_to_append.1,
        infra.has_class(_, target_and_classes_to_append.0),
      )
    }
  )
}

fn nodemap(
  vxml: VXML,
  inner: InnerParam,
) -> Result(VXML, DesugaringError) {
  case vxml {
    T(_, _) -> Ok(vxml)
    V(_, tag, _, children) -> {
      case dict.get(inner, tag) {
        Error(Nil) -> Ok(vxml)
        Ok(targets_and_classes_to_append) -> {
          Ok(V(
              ..vxml,
              children: infra.v_map(children, update_child(_, targets_and_classes_to_append))
          ))
        }
      }
    }
  }
}

fn nodemap_factory(inner: InnerParam) -> n2t.OneToOneNodeMap {
  nodemap(_, inner)
}

fn transform_factory(inner: InnerParam) -> DesugarerTransform {
  n2t.one_to_one_nodemap_2_desugarer_transform(nodemap_factory(inner))
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  infra.dict_from_list_with_desugaring_error(param)
}

type Param =
  List(#(String, List(#(String, String))))
//       ↖       ↖
//       parent  list of (target_class, class_to_append)
//       tag     pairs

type InnerParam = Dict(String, List(#(String, String)))

pub const name = "append_class_to_children_with_class"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
//------------------------------------------------53
/// checks all children of a given parent tag for
/// existence of a specific class value and if found,
/// appends a new class value to the class attribute.
/// takes tuples of (parent_tag, list_of_class_mappings).
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
  [
    infra.AssertiveTestData(
      param: [#("Chapter", [#("well", "out")])],
      source:   "
                <> root
                  <> Chapter
                    <> div
                      class=well
                    <> div
                      class=other
                    <> p
                      class=well
                  <> Section
                    <> div
                      class=well
                ",
      expected: "
                <> root
                  <> Chapter
                    <> div
                      class=well out
                    <> div
                      class=other
                    <> p
                      class=well out
                  <> Section
                    <> div
                      class=well
                "
    ),
    infra.AssertiveTestData(
      param: [#("container", [#("highlight", "active")])],
      source:   "
                <> root
                  <> container
                    <> span
                      class=highlight
                    <> span
                      class=highlight bold
                    <> div
                      class=normal
                ",
      expected: "
                <> root
                  <> container
                    <> span
                      class=highlight active
                    <> span
                      class=highlight bold active
                    <> div
                      class=normal
                "
    ),
    infra.AssertiveTestData(
      param: [#("parent", [#("target", "new")]), #("other", [#("different", "added")])],
      source:   "
                <> root
                  <> parent
                    <> child
                      class=target
                  <> other
                    <> child
                      class=different
                ",
      expected: "
                <> root
                  <> parent
                    <> child
                      class=target new
                  <> other
                    <> child
                      class=different added
                "
    ),
    infra.AssertiveTestData(
      param: [#("Chapter", [#("well", "out"), #("highlight", "active")])],
      source:   "
                <> root
                  <> Chapter
                    <> div
                      class=well highlight
                    <> div
                      class=important
                    <> div
                      class=other
                ",
      expected: "
                <> root
                  <> Chapter
                    <> div
                      class=well highlight out active
                    <> div
                      class=important
                    <> div
                      class=other
                "
    )
  ]
}

pub fn assertive_tests() {
  infra.assertive_test_collection_from_data(name, assertive_tests_data(), constructor)
}
