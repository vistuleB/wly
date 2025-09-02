import gleam/result
import gleam/list
import vxml.{type VXML, V, T}
import infrastructure.{type DesugarerTransform, type DesugaringError, DesugaringError, type DesugaringWarning, type TrafficLight, Continue, GoBack} as infra
import blame as bl
import on

pub fn add_no_warnings(vxml: VXML) {
  #(vxml, [])
}

pub fn identity_transform(vxml: VXML) {
  Ok(#(vxml, []))
}

fn bad_tag_guard(
  tags: List(String),
  on_all_ok: fn() -> DesugarerTransform,
) -> DesugarerTransform {
  case list.find(tags, infra.invalid_tag) {
    Ok(bad_tag) -> fn(_vxml) { Error(DesugaringError(bl.no_blame, "invalid tag: \"" <> bad_tag <> "\"")) }
    Error(Nil) -> on_all_ok()
  }
}

//**************************************************************
//* OneToOneNoErrorNodeMap
//**************************************************************

pub type OneToOneNoErrorNodeMap =
  fn(VXML) -> VXML

// *** without forbidden ***

fn one_to_one_no_error_nodemap_recursive_application(
  node: VXML,
  nodemap: OneToOneNoErrorNodeMap,
) -> VXML {
  case node {
    T(_, _) -> nodemap(node)
    V(_, _, _, children) -> nodemap(V(
      ..node,
      children: list.map(
        children,
        one_to_one_no_error_nodemap_recursive_application(_, nodemap),
      ),
    ))
  }
}

pub fn one_to_one_no_error_nodemap_2_desugarer_transform(
  nodemap: OneToOneNoErrorNodeMap,
) -> DesugarerTransform {
  fn (vxml) {
    one_to_one_no_error_nodemap_recursive_application(vxml, nodemap)
    |> add_no_warnings
    |> Ok
  }
}

// *** with forbidden ***

fn one_to_one_no_error_nodemap_recursive_application_with_forbidden(
  node: VXML,
  nodemap: OneToOneNoErrorNodeMap,
  forbidden: List(String),
) -> VXML {
  case node {
    T(_, _) -> nodemap(node)
    V(_, tag, _, children) -> {
      case list.contains(forbidden, tag) {
        True -> node
        False -> nodemap(V(
          ..node,
          children: list.map(
            children, 
            one_to_one_no_error_nodemap_recursive_application_with_forbidden(_, nodemap, forbidden),
          )
        ))
      }
    }
  }
}

pub fn one_to_one_no_error_nodemap_2_desugarer_transform_with_forbidden(
  nodemap: OneToOneNoErrorNodeMap,
  forbidden: List(String),
) -> DesugarerTransform {
  use <- bad_tag_guard(forbidden)

  fn(vxml) {
    one_to_one_no_error_nodemap_recursive_application_with_forbidden(vxml, nodemap, forbidden)
    |> add_no_warnings
    |> Ok
  }
}

// *** with forbidden, self_first ***

fn one_to_one_no_error_nodemap_recursive_application_with_forbidden_self_first(
  node: VXML,
  nodemap: OneToOneNoErrorNodeMap,
  forbidden: List(String),
) -> VXML {
  case node {
    T(_, _) -> nodemap(node)
    V(_, tag, _, _) -> case list.contains(forbidden, tag) {
      True -> node
      False -> {
        let assert V(_, _, _, children) as node = nodemap(node)
        let children = list.map(
          children,
          one_to_one_no_error_nodemap_recursive_application_with_forbidden_self_first(_, nodemap, forbidden)
        )
        V(..node, children: children)
      }
    }
  }
}

pub fn one_to_one_no_error_nodemap_2_desugarer_transform_with_forbidden_self_first(
  nodemap: OneToOneNoErrorNodeMap,
  forbidden: List(String),
) -> DesugarerTransform {
  use <- bad_tag_guard(forbidden)

  fn (vxml) {
    one_to_one_no_error_nodemap_recursive_application_with_forbidden_self_first(vxml, nodemap, forbidden)
    |> add_no_warnings
    |> Ok
  }
}

//**************************************************************
//* OneToOneNodeMap
//**************************************************************

pub type OneToOneNodeMap =
  fn(VXML) -> Result(VXML, DesugaringError)

// *** without forbidden ***

fn one_to_one_nodemap_recursive_application(
  node: VXML,
  nodemap: OneToOneNodeMap,
) -> Result(VXML, DesugaringError) {
  case node {
    T(_, _) -> nodemap(node)
    V(_, _, _, children) -> {
      use children <- result.try(
        children |> list.try_map(one_to_one_nodemap_recursive_application(_, nodemap))
      )

      nodemap(V(..node, children: children))
    }
  }
}

pub fn one_to_one_nodemap_2_desugarer_transform(
  nodemap: OneToOneNodeMap,
) -> DesugarerTransform {
  fn (vxml) {
    one_to_one_nodemap_recursive_application(vxml, nodemap)
    |> result.map(add_no_warnings)
  }
}

// *** with forbidden ***

fn one_to_one_nodemap_recursive_application_with_forbidden(
  node: VXML,
  nodemap: OneToOneNodeMap,
  forbidden: List(String),
) -> Result(VXML, DesugaringError) {
  case node {
    T(_, _) -> nodemap(node)
    V(_, tag, _, children) -> case list.contains(forbidden, tag) {
      True -> Ok(node)
      False -> {
        use children <- result.try(
          children
          |> list.try_map(one_to_one_nodemap_recursive_application_with_forbidden(_, nodemap, forbidden))
        )
        nodemap(V(..node, children: children))
      }
    }
  }
}

pub fn one_to_one_nodemap_2_desugarer_transform_with_forbidden(
  nodemap: OneToOneNodeMap,
  forbidden: List(String),
) -> DesugarerTransform {
  use <- bad_tag_guard(forbidden)

  fn (vxml) {
    one_to_one_nodemap_recursive_application_with_forbidden(vxml, nodemap, forbidden)
    |> result.map(add_no_warnings)
  }
}

//**************************************************************
//* OneToManyNoErrorNodeMap
//**************************************************************

pub type OneToManyNoErrorNodeMap =
  fn(VXML) -> List(VXML)

// *** without forbidden ***

fn one_to_many_no_error_nodemap_recursive_application(
  node: VXML,
  nodemap: OneToManyNoErrorNodeMap,
) -> List(VXML) {
  case node {
    T(_, _) -> nodemap(node)
    V(_, _, _, children) -> {
      let children =
        children
        |> list.map(one_to_many_no_error_nodemap_recursive_application(_, nodemap))
        |> list.flatten
      nodemap(V(..node, children: children))
    }
  }
}

pub fn one_to_many_no_error_nodemap_2_desugarer_transform(
  nodemap: OneToManyNoErrorNodeMap,
) -> DesugarerTransform {
  fn (vxml) {
    one_to_many_no_error_nodemap_recursive_application(vxml, nodemap)
    |> infra.get_root_with_desugaring_error
    |> result.map(add_no_warnings)
  }
}

// *** with forbidden ***

fn one_to_many_no_error_nodemap_recursive_application_with_forbidden(
  node: VXML,
  nodemap: OneToManyNoErrorNodeMap,
  forbidden: List(String),
) -> List(VXML) {
  case node {
    T(_, _) -> nodemap(node)
    V(_, tag, _, children) -> case list.contains(forbidden, tag) {
      True -> [node]
      False -> {
        let children =
          children
          |> list.map(one_to_many_no_error_nodemap_recursive_application_with_forbidden(_, nodemap, forbidden))
          |> list.flatten
        nodemap(V(..node, children: children))
      }
    }
  }
}

pub fn one_to_many_no_error_nodemap_2_desugarer_transform_with_forbidden(
  nodemap: OneToManyNoErrorNodeMap,
  forbidden: List(String),
) -> DesugarerTransform {
  use <- bad_tag_guard(forbidden)

  fn (vxml) {
    one_to_many_no_error_nodemap_recursive_application_with_forbidden(vxml, nodemap, forbidden)
    |> infra.get_root_with_desugaring_error
    |> result.map(add_no_warnings)
  }
}

//**************************************************************
//* OneToManyNodeMap
//**************************************************************

pub type OneToManyNodeMap =
  fn(VXML) -> Result(List(VXML), DesugaringError)

// *** without forbidden ***

fn one_to_many_nodemap_recursive_application(
  node: VXML,
  nodemap: OneToManyNodeMap,
) -> Result(List(VXML), DesugaringError) {
  case node {
    T(_, _) -> nodemap(node)
    V(_, _, _, children) -> {
      use children <- result.try(
        children
        |> list.try_map(one_to_many_nodemap_recursive_application(_, nodemap))
        |> result.map(list.flatten)
      )
      nodemap(V(..node, children: children))
    }
  }
}

pub fn one_to_many_nodemap_2_desugarer_transform(
  nodemap: OneToManyNodeMap,
) -> DesugarerTransform {
  fn (vxml) {
    one_to_many_nodemap_recursive_application(vxml, nodemap)
    |> result.try(infra.get_root_with_desugaring_error)
    |> result.map(add_no_warnings)
  }
}

// *** with forbidden ***

fn one_to_many_nodemap_recursive_application_with_forbidden(
  node: VXML,
  nodemap: OneToManyNodeMap,
  forbidden: List(String),
) -> Result(List(VXML), DesugaringError) {
  case node {
    T(_, _) -> nodemap(node)
    V(_, tag, _, children) -> case list.contains(forbidden, tag) {
      True -> Ok([node])
      False -> {
        use children <- result.try(
          children
          |> list.try_map(one_to_many_nodemap_recursive_application_with_forbidden(_, nodemap, forbidden))
          |> result.map(list.flatten)
        )
        nodemap(V(..node, children: children))
      }
    }
  }
}

pub fn one_to_many_nodemap_2_desugarer_transform_with_forbidden(
  nodemap: OneToManyNodeMap,
  forbidden: List(String),
) -> DesugarerTransform {
  use <- bad_tag_guard(forbidden)

  fn (vxml) {
    one_to_many_nodemap_recursive_application_with_forbidden(vxml, nodemap, forbidden)
    |> result.try(infra.get_root_with_desugaring_error)
    |> result.map(add_no_warnings)
  }
}

//**************************************************************
//* FancyOneToOneNoErrorNodeMap
//**************************************************************

pub type FancyOneToOneNoErrorNodeMap =
  fn(VXML, List(VXML), List(VXML), List(VXML), List(VXML)) -> VXML

fn fancy_one_to_one_no_error_nodemap_recursive_application(
  node: VXML,
  ancestors: List(VXML),
  previous_siblings_before_mapping: List(VXML),
  previous_siblings_after_mapping: List(VXML),
  following_siblings_before_mapping: List(VXML),
  nodemap: FancyOneToOneNoErrorNodeMap,
) -> VXML {
  case node {
    T(_, _) ->
      nodemap(
        node,
        ancestors,
        previous_siblings_before_mapping,
        previous_siblings_after_mapping,
        following_siblings_before_mapping,
      )
    V(blame, tag, attrs, children) -> {
      let children_ancestors = [node, ..ancestors]
      let children =
        list.fold(
          children,
          #([], [], list.drop(children, 1)),
          fn(acc, child) {
            let mapped_child =
              fancy_one_to_one_no_error_nodemap_recursive_application(child, children_ancestors, acc.0, acc.1, acc.2, nodemap)
            #(
              [child, ..acc.0],
              [mapped_child, ..acc.1],
              list.drop(acc.2, 1),
            )
          }
        )
        |> fn(acc) {acc.1 |> list.reverse}
      nodemap(
        V(blame, tag, attrs, children),
        ancestors,
        previous_siblings_before_mapping,
        previous_siblings_after_mapping,
        following_siblings_before_mapping,
      )
    }
  }
}

pub fn fancy_one_to_one_no_error_nodemap_2_desugarer_transform(
  nodemap: FancyOneToOneNoErrorNodeMap,
) -> DesugarerTransform {
  fn (vxml) {
    fancy_one_to_one_no_error_nodemap_recursive_application(vxml, [], [], [], [], nodemap)
    |> add_no_warnings
    |> Ok
  }
}

//**************************************************************
//* FancyOneToOneNodeMap
//**************************************************************

pub type FancyOneToOneNodeMap =
  fn(VXML, List(VXML), List(VXML), List(VXML), List(VXML)) ->
    Result(VXML, DesugaringError)

fn fancy_one_to_one_nodemap_recursive_application(
  node: VXML,
  ancestors: List(VXML),
  previous_siblings_before_mapping: List(VXML),
  previous_siblings_after_mapping: List(VXML),
  following_siblings_before_mapping: List(VXML),
  nodemap: FancyOneToOneNodeMap,
) -> Result(VXML, DesugaringError) {
  case node {
    T(_, _) ->
      nodemap(
        node,
        ancestors,
        previous_siblings_before_mapping,
        previous_siblings_after_mapping,
        following_siblings_before_mapping,
      )
    V(blame, tag, attrs, children) -> {
      let children_ancestors = [node, ..ancestors]
      use children <- result.try(
        list.try_fold(
          children,
          #([], [], list.drop(children, 1)),
          fn(acc, child) {
            case fancy_one_to_one_nodemap_recursive_application(child, children_ancestors, acc.0, acc.1, acc.2, nodemap) {
              Error(e) -> Error(e)
              Ok(mapped_child) -> {
                Ok(#(
                  [child, ..acc.0],
                  [mapped_child, ..acc.1],
                  list.drop(acc.2, 1),
                ))
              }
            }
          }
        )
        |> result.map(fn(acc) {acc.1 |> list.reverse})
      )
      nodemap(
        V(blame, tag, attrs, children),
        ancestors,
        previous_siblings_before_mapping,
        previous_siblings_after_mapping,
        following_siblings_before_mapping,
      )
    }
  }
}

pub fn fancy_one_to_one_nodemap_2_desugarer_transform(
  nodemap: FancyOneToOneNodeMap,
) -> DesugarerTransform {
  fn (vxml) {
    fancy_one_to_one_nodemap_recursive_application(vxml, [], [], [], [], nodemap)
    |> result.map(add_no_warnings)
  }
}

//**********************************************************************
//* FancyOneToManyNoErrorNodeMap
//**********************************************************************

pub type FancyOneToManyNoErrorNodeMap =
  fn(VXML, List(VXML), List(VXML), List(VXML), List(VXML)) ->
    List(VXML)

fn fancy_one_to_many_no_error_nodemap_recursive_application(
  node: VXML,
  ancestors: List(VXML),
  previous_siblings_before_mapping: List(VXML),
  previous_siblings_after_mapping: List(VXML),
  following_siblings_before_mapping: List(VXML),
  nodemap: FancyOneToManyNoErrorNodeMap,
) -> List(VXML) {
  case node {
    T(_, _) ->
      nodemap(
        node,
        ancestors,
        previous_siblings_before_mapping,
        previous_siblings_after_mapping,
        following_siblings_before_mapping,
      )
    V(_, _, _, children) -> {
      let children_ancestors = [node, ..ancestors]
      let children =
        list.fold(
          children,
          #([], [], list.drop(children, 1)),
          fn(acc, child) {
            let shat_children =
              fancy_one_to_many_no_error_nodemap_recursive_application(
                child,
                children_ancestors,
                acc.0,
                acc.1,
                acc.2,
                nodemap
              )
            #(
              [child, ..acc.0],
              infra.pour(shat_children, acc.1),
              list.drop(acc.2, 1),
            )
          }
        )
        |> fn(acc) {acc.1 |> list.reverse}
      nodemap(
        V(..node, children: children),
        ancestors,
        previous_siblings_before_mapping,
        previous_siblings_after_mapping,
        following_siblings_before_mapping,
      )
    }
  }
}

pub fn fancy_one_to_many_no_error_nodemap_2_desugarer_transform(
  nodemap: FancyOneToManyNoErrorNodeMap,
) -> DesugarerTransform {
  fn(root: VXML) {
    fancy_one_to_many_no_error_nodemap_recursive_application(
      root,
      [],
      [],
      [],
      [],
      nodemap
    )
    |> infra.get_root_with_desugaring_error
    |> result.map(add_no_warnings)
  }
}

//**********************************************************************
//* FancyOneToManyNodeMap
//**********************************************************************

pub type FancyOneToManyNodeMap =
  fn(VXML, List(VXML), List(VXML), List(VXML), List(VXML)) ->
    Result(List(VXML), DesugaringError)

fn fancy_one_to_many_nodemap_recursive_application(
  node: VXML,
  ancestors: List(VXML),
  previous_siblings_before_mapping: List(VXML),
  previous_siblings_after_mapping: List(VXML),
  following_siblings_before_mapping: List(VXML),
  nodemap: FancyOneToManyNodeMap,
) -> Result(List(VXML), DesugaringError) {
  case node {
    T(_, _) ->
      nodemap(
        node,
        ancestors,
        previous_siblings_before_mapping,
        previous_siblings_after_mapping,
        following_siblings_before_mapping,
      )
    V(_, _, _, children) -> {
      let children_ancestors = [node, ..ancestors]
      use children <- result.try(
        list.try_fold(
          children,
          #([], [], list.drop(children, 1)),
          fn(acc, child) {
            case fancy_one_to_many_nodemap_recursive_application(
              child,
              children_ancestors,
              acc.0,
              acc.1,
              acc.2,
              nodemap
            ) {
              Error(e) -> Error(e)
              Ok(shat_children) -> {
                Ok(#(
                  [child, ..acc.0],
                  infra.pour(shat_children, acc.1),
                  list.drop(acc.2, 1),
                ))
              }
            }
          }
        )
        |> result.map(fn(acc) {acc.1 |> list.reverse})
      )
      nodemap(
        V(..node, children: children),
        ancestors,
        previous_siblings_before_mapping,
        previous_siblings_after_mapping,
        following_siblings_before_mapping,
      )
    }
  }
}

pub fn fancy_one_to_many_nodemap_2_desugarer_transform(
  nodemap: FancyOneToManyNodeMap,
) -> DesugarerTransform {
  fn(root: VXML) {
    fancy_one_to_many_nodemap_recursive_application(
      root,
      [],
      [],
      [],
      [],
      nodemap
    )
    |> result.try(infra.get_root_with_desugaring_error)
    |> result.map(add_no_warnings)
  }
}

//**************************************************************
//* OneToOneStatefulNodeMap
//**************************************************************

pub type OneToOneStatefulNodeMap(a) =
  fn(VXML, a) -> Result(#(VXML, a), DesugaringError)

fn one_to_one_stateful_nodemap_recursive_application(
  state: a,
  node: VXML,
  nodemap: OneToOneStatefulNodeMap(a),
) -> Result(#(VXML, a), DesugaringError) {
  case node {
    T(_, _) -> nodemap(node, state)
    V(_, _, _, children) -> {
      use #(children, state) <- result.try(
        children
        |> infra.try_map_fold(
          state,
          fn(acc, child) {
            one_to_one_stateful_nodemap_recursive_application(acc, child, nodemap)
          }
        )
      )
      nodemap(V(..node, children: children), state)
    }
  }
}

pub fn one_to_one_stateful_nodemap_2_desugarer_transform(
  nodemap: OneToOneStatefulNodeMap(a),
  initial_state: a,
) -> DesugarerTransform {
  fn(vxml) {
    case one_to_one_stateful_nodemap_recursive_application(initial_state, vxml, nodemap) {
      Error(err) -> Error(err)
      Ok(#(new_vxml, _)) -> Ok(#(new_vxml, []))
    }
  }
}

//**********************************************************************
//* FancyOneToOneStatefulNodeMap
//**********************************************************************

pub type FancyOneToOneStatefulNodeMap(a) =
  fn(VXML, List(VXML), List(VXML), List(VXML), List(VXML), a) ->
    Result(#(VXML, a), DesugaringError)

fn fancy_one_to_one_stateful_nodemap_recursive_application(
  state: a,
  node: VXML,
  ancestors: List(VXML),
  previous_siblings_before_mapping: List(VXML),
  previous_siblings_after_mapping: List(VXML),
  following_siblings_before_mapping: List(VXML),
  nodemap: FancyOneToOneStatefulNodeMap(a),
) -> Result(#(VXML, a), DesugaringError) {
  case node {
    T(_, _) ->
      nodemap(
        node,
        ancestors,
        previous_siblings_before_mapping,
        previous_siblings_after_mapping,
        following_siblings_before_mapping,
        state,
      )
    V(_, _, _, children) -> {
      let children_ancestors = [node, ..ancestors]
      use #(children, state) <- result.try(
        list.try_fold(
          children,
          #([], [], list.drop(children, 1), state),
          fn(acc, child) {
            case fancy_one_to_one_stateful_nodemap_recursive_application(
              acc.3,
              child,
              children_ancestors,
              acc.0,
              acc.1,
              acc.2,
              nodemap,
            ) {
              Error(e) -> Error(e)
              Ok(#(mapped_child, state)) -> {
                Ok(#(
                  [child, ..acc.0],
                  [mapped_child],
                  list.drop(acc.2, 1),
                  state,
                ))
              }
            }
          }
        )
        |> result.map(fn(acc) {#(acc.1 |> list.reverse, acc.3)})
      )
      nodemap(
        V(..node, children: children),
        ancestors,
        previous_siblings_before_mapping,
        previous_siblings_after_mapping,
        following_siblings_before_mapping,
        state,
      )
    }
  }
}

pub fn fancy_one_to_one_stateful_nodemap_2_desugarer_transform(
  nodemap: FancyOneToOneStatefulNodeMap(a),
  initial_state: a,
) -> DesugarerTransform {
  fn(vxml) {
    case fancy_one_to_one_stateful_nodemap_recursive_application(
      initial_state,
      vxml,
      [],
      [],
      [],
      [],
      nodemap,
    ) {
      Error(err) -> Error(err)
      Ok(#(vxml, _)) -> Ok(#(vxml, []))
    }
  }
}

//**********************************************************************
//* OneToOneBeforeAndAfterNoErrorStatefulNodeMap
//**********************************************************************

pub type OneToOneBeforeAndAfterNoErrorStatefulNodeMap(a) {
  OneToOneBeforeAndAfterNoErrorStatefulNodeMap(
    v_before_transforming_children: fn(VXML, a) -> #(VXML, a),
    v_after_transforming_children: fn(VXML, a, a) -> #(VXML, a),
    t_nodemap: fn(VXML, a) -> #(VXML, a),
  )
}

fn one_to_one_before_and_after_no_error_stateful_nodemap_recursive_application(
  original_state: a,
  node: VXML,
  nodemap: OneToOneBeforeAndAfterNoErrorStatefulNodeMap(a),
) -> #(VXML, a) {
  case node {
    T(_, _) -> nodemap.t_nodemap(node, original_state)
    V(_, _, _, _) -> {
      let assert #(V(_, _, _, children), latest_state) =
        nodemap.v_before_transforming_children(
          node,
          original_state,
        )
      let #(latest_state, children) =
        list.map_fold(
          children,
          latest_state,
          fn (acc, child) {
            let #(vxml, state) = one_to_one_before_and_after_no_error_stateful_nodemap_recursive_application(acc, child, nodemap)
            #(state, vxml)
          }
        )
      nodemap.v_after_transforming_children(
        node |> infra.v_replace_children_with(children),
        original_state,
        latest_state,
      )
    }
  }
}

pub fn one_to_one_before_and_after_no_error_stateful_nodemap_2_desugarer_transform(
  nodemap: OneToOneBeforeAndAfterNoErrorStatefulNodeMap(a),
  initial_state: a,
) -> DesugarerTransform {
  fn(vxml) {
    let #(vxml, _) =
      one_to_one_before_and_after_no_error_stateful_nodemap_recursive_application(
        initial_state,
        vxml,
        nodemap
      )
    Ok(#(vxml, []))
  }
}

//**********************************************************************
//* OneToOneBeforeAndAfterStatefulNodeMap
//**********************************************************************

pub type OneToOneBeforeAndAfterStatefulNodeMap(a) {
  OneToOneBeforeAndAfterStatefulNodeMap(
    v_before_transforming_children: fn(VXML, a) ->
      Result(#(VXML, a), DesugaringError),
    v_after_transforming_children: fn(VXML, a, a) ->
      Result(#(VXML, a), DesugaringError),
    t_nodemap: fn(VXML, a) ->
      Result(#(VXML, a), DesugaringError),
  )
}

fn one_to_one_before_and_after_stateful_nodemap_recursive_application(
  original_state: a,
  node: VXML,
  nodemap: OneToOneBeforeAndAfterStatefulNodeMap(a),
) -> Result(#(VXML, a), DesugaringError) {
  case node {
    T(_, _) -> nodemap.t_nodemap(node, original_state)
    V(_, _, _, _) -> {
      use #(node, latest_state) <- result.try(
        nodemap.v_before_transforming_children(
          node,
          original_state,
        ),
      )
      let assert V(_, _, _, children) = node
      use #(children, latest_state) <- result.try(
        infra.try_map_fold(
          children,
          latest_state,
          fn (acc, child) { one_to_one_before_and_after_stateful_nodemap_recursive_application(acc, child, nodemap) }
        )
      )
      nodemap.v_after_transforming_children(
        node |> infra.v_replace_children_with(children),
        original_state,
        latest_state,
      )
    }
  }
}

pub fn one_to_one_before_and_after_stateful_nodemap_2_desugarer_transform(
  nodemap: OneToOneBeforeAndAfterStatefulNodeMap(a),
  initial_state: a,
) -> DesugarerTransform {
  fn(vxml) {
    use #(vxml, _) <- result.try(
      one_to_one_before_and_after_stateful_nodemap_recursive_application(
        initial_state,
        vxml,
        nodemap
      )
    )
    Ok(#(vxml, []))
  }
}

//**********************************************************************
//* FancyOneToOneBeforeAndAfterStatefulNodeMap(a)
//**********************************************************************

pub type FancyOneToOneBeforeAndAfterStatefulNodeMap(a) {
  FancyOneToOneBeforeAndAfterStatefulNodeMap(
    v_before_transforming_children: fn(VXML, List(VXML), List(VXML), List(VXML), List(VXML), a) ->
      Result(#(VXML, a), DesugaringError),
    v_after_transforming_children: fn(VXML, List(VXML), List(VXML), List(VXML), List(VXML), a, a) ->
      Result(#(VXML, a), DesugaringError),
    t_nodemap: fn(VXML, List(VXML), List(VXML), List(VXML), List(VXML), a) ->
      Result(#(VXML, a), DesugaringError),
  )
}

fn fancy_one_to_one_before_and_after_stateful_nodemap_recursive_application(
  original_state: a,
  node: VXML,
  ancestors: List(VXML),
  previous_siblings_before_mapping: List(VXML),
  previous_siblings_after_mapping: List(VXML),
  following_siblings_before_mapping: List(VXML),
  nodemap: FancyOneToOneBeforeAndAfterStatefulNodeMap(a),
) -> Result(#(VXML, a), DesugaringError) {
  case node {
    T(_, _) -> nodemap.t_nodemap(
      node,
      ancestors,
      previous_siblings_before_mapping,
      previous_siblings_after_mapping,
      following_siblings_before_mapping,
      original_state,
    )
    V(_, _, _, _) -> {
      use #(node, latest_state) <- result.try(
        nodemap.v_before_transforming_children(
          node,
          ancestors,
          previous_siblings_before_mapping,
          previous_siblings_after_mapping,
          following_siblings_before_mapping,
          original_state,
        ),
      )
      let assert V(_, _, _, children) = node
      let children_ancestors = [node, ..ancestors]
      use #(children, latest_state) <- result.try(
        list.try_fold(
          children,
          #([], [], list.drop(children, 1), latest_state),
          fn (acc, child) {
            use #(mapped_child, state) <- result.try(fancy_one_to_one_before_and_after_stateful_nodemap_recursive_application(
              acc.3,
              child,
              children_ancestors,
              acc.0,
              acc.1,
              acc.2,
              nodemap,
            ))
            Ok(#(
              [child, ..acc.0],
              [mapped_child, ..acc.1],
              list.drop(acc.2, 1),
              state,
            ))
          }
        )
        |> result.map(fn(acc){#(acc.1 |> list.reverse, acc.3)})
      )
      let node = V(..node, children: children)
      nodemap.v_after_transforming_children(
        node,
        ancestors,
        previous_siblings_before_mapping,
        previous_siblings_after_mapping,
        following_siblings_before_mapping,
        original_state,
        latest_state,
      )
    }
  }
}

pub fn fancy_one_to_one_before_and_after_stateful_nodemap_2_desugarer_transform(
  nodemap: FancyOneToOneBeforeAndAfterStatefulNodeMap(a),
  initial_state: a,
) -> DesugarerTransform {
  fn(vxml) {
    use #(vxml, _) <- result.try(
      fancy_one_to_one_before_and_after_stateful_nodemap_recursive_application(
        initial_state,
        vxml,
        [],
        [],
        [],
        [],
        nodemap,
      )
    )
    Ok(#(vxml, []))
  }
}

//**************************************************************
//* OneToManyBeforeAndAfterStatefulNodeMap
//**************************************************************

pub type OneToManyBeforeAndAfterStatefulNodeMap(a) {
  OneToManyBeforeAndAfterStatefulNodeMap(
    v_before_transforming_children: fn(VXML, a) ->
      Result(#(VXML, a), DesugaringError),
    v_after_transforming_children: fn(VXML, a, a) ->
      Result(#(List(VXML), a), DesugaringError),
    t_nodemap: fn(VXML, a) ->
      Result(#(List(VXML), a), DesugaringError),
  )
}

fn one_to_many_before_and_after_stateful_nodemap_recursive_application(
  original_state: a,
  node: VXML,
  nodemap: OneToManyBeforeAndAfterStatefulNodeMap(a),
) -> Result(#(List(VXML), a), DesugaringError) {
   case node {
    V(_, _, _, _) -> {
      use #(node, latest_state) <- result.try(
        nodemap.v_before_transforming_children(
          node,
          original_state,
        ),
      )
      let assert V(_, _, _, children) = node
      use #(children, latest_state) <- result.try(
        children
        |> list.try_fold(
          #([], latest_state),
          fn (acc, child) {
            use #(shat_children, latest_state) <- result.try(one_to_many_before_and_after_stateful_nodemap_recursive_application(
              acc.1,
              child,
              nodemap,
            ))
            Ok(#(
              infra.pour(shat_children, acc.0),
              latest_state,
            ))
          }
        )
        |> result.map(fn(acc) {#(acc.0 |> list.reverse, acc.1)})
      )
      nodemap.v_after_transforming_children(
        node |> infra.v_replace_children_with(children),
        original_state,
        latest_state,
      )
    }
    T(_, _) -> nodemap.t_nodemap(node, original_state)
  }
}

pub fn one_to_many_before_and_after_stateful_nodemap_2_desufarer_transform(
  nodemap: OneToManyBeforeAndAfterStatefulNodeMap(a),
  initial_state: a,
) -> DesugarerTransform {
  fn(vxml) {
    one_to_many_before_and_after_stateful_nodemap_recursive_application(initial_state, vxml, nodemap)
    |> result.map(fn(pair){pair.0})
    |> result.try(infra.get_root_with_desugaring_error)
    |> result.map(add_no_warnings)
  }
}

//**************************************************************
//* OneToManyBeforeAndAfterStatefulNodeMapWithWarnings
//**************************************************************

pub type OneToManyBeforeAndAfterStatefulNodeMapWithWarnings(a) {
  OneToManyBeforeAndAfterStatefulNodeMapWithWarnings(
    v_before_transforming_children: fn(VXML, a) ->
      Result(#(VXML, a, List(DesugaringWarning)), DesugaringError),
    v_after_transforming_children: fn(VXML, a, a) ->
      Result(#(List(VXML), a, List(DesugaringWarning)), DesugaringError),
    t_nodemap: fn(VXML, a) ->
      Result(#(List(VXML), a, List(DesugaringWarning)), DesugaringError),
  )
}

fn one_to_many_before_and_after_stateful_nodemap_with_warnings_recursive_application(
  collected_warnings: List(DesugaringWarning),
  original_state: a,
  node: VXML,
  nodemap: OneToManyBeforeAndAfterStatefulNodeMapWithWarnings(a),
) -> Result(#(List(VXML), a, List(DesugaringWarning)), DesugaringError) {
   case node {
    V(_, _, _, _) -> {
      use #(node, latest_state, warnings) <- result.try(
        nodemap.v_before_transforming_children(
          node,
          original_state,
        ),
      )
      let collected_warnings = infra.pour(warnings, collected_warnings)
      let assert V(_, _, _, children) = node
      use #(children, latest_state, collected_warnings) <- result.try(
        children
        |> list.try_fold(
          #([], latest_state, collected_warnings),
          fn (acc, child) {
            use #(shat_children, latest_state, collected_warnings) <- result.try(
              one_to_many_before_and_after_stateful_nodemap_with_warnings_recursive_application(
                acc.2,
                acc.1,
                child,
                nodemap,
              )
            )
            Ok(#(
              infra.pour(shat_children, acc.0),
              latest_state,
              collected_warnings,
            ))
          }
        )
        |> result.map(fn(acc) {#(acc.0 |> list.reverse, acc.1, acc.2)})
      )
      use #(node, latest_state, warnings) <- result.try(
        nodemap.v_after_transforming_children(
          node |> infra.v_replace_children_with(children),
          original_state,
          latest_state,
        )
      )
      Ok(#(node, latest_state, infra.pour(warnings, collected_warnings)))
    }
    T(_, _) -> {
      use #(vxml, latest_state, warnings) <- result.try(
        nodemap.t_nodemap(node, original_state)
      )

      Ok(#(vxml, latest_state, infra.pour(warnings, collected_warnings)))
    }
  }
}

pub fn one_to_many_before_and_after_stateful_nodemap_with_warnings_2_desufarer_transform(
  nodemap: OneToManyBeforeAndAfterStatefulNodeMapWithWarnings(a),
  initial_state: a,
) -> DesugarerTransform {
  fn(vxml) {
    use #(vxmls, _, warnings) <- result.try(
      one_to_many_before_and_after_stateful_nodemap_with_warnings_recursive_application(
        [],
        initial_state,
        vxml,
        nodemap,
      )
    )
    use vxml <- result.try(infra.get_root_with_desugaring_error(vxmls))
    Ok(#(vxml, warnings |> list.reverse))
  }
}

//**************************************************************
//* EarlyReturnOneToOneNoErrorNodeMap
//**************************************************************

pub type EarlyReturnOneToOneNoErrorNodeMap =
  fn(VXML) -> #(VXML, TrafficLight)

// *** without forbidden ***

fn early_return_one_to_one_no_error_nodemap_recursive_application(
  node: VXML,
  nodemap: EarlyReturnOneToOneNoErrorNodeMap,
) -> VXML {
  let #(node, signal) = nodemap(node)
  case node, signal {
    V(_, _, _, children), Continue -> {
      let children =
        children
        |> list.map(
          early_return_one_to_one_no_error_nodemap_recursive_application(_, nodemap)
        )
      V(..node, children: children)
    }
    _, _ -> node
  }
}

pub fn early_return_one_to_one_no_error_nodemap_2_desugarer_transform(
  nodemap: EarlyReturnOneToOneNoErrorNodeMap,
) -> DesugarerTransform {
  fn (vxml) {
    early_return_one_to_one_no_error_nodemap_recursive_application(vxml, nodemap)
    |> add_no_warnings
    |> Ok
  }
}

// *** with forbidden ***

fn early_return_one_to_one_no_error_nodemap_recursive_application_with_forbidden(
  node: VXML,
  nodemap: EarlyReturnOneToOneNoErrorNodeMap,
  forbidden: List(String),
) -> VXML {
  use <- on.true_false(
    infra.is_v_and_tag_is_one_of(node, forbidden),
    node,
  )
  let #(node, signal) = nodemap(node)
  case node, signal {
    V(_, _, _, children), Continue -> {
      let children =
        children
        |> list.map(
          early_return_one_to_one_no_error_nodemap_recursive_application_with_forbidden(_, nodemap, forbidden)
        )
      V(..node, children: children)
    }
    _, _ -> node
  }
}

pub fn early_return_one_to_one_no_error_nodemap_2_desugarer_transform_with_forbidden(
  nodemap: EarlyReturnOneToOneNoErrorNodeMap,
  forbidden: List(String),
) -> DesugarerTransform {
  use <- bad_tag_guard(forbidden)

  fn (vxml) {
    early_return_one_to_one_no_error_nodemap_recursive_application_with_forbidden(vxml, nodemap, forbidden)
    |> add_no_warnings
    |> Ok
  }
}

//**************************************************************
//* EarlyReturnOneToManyNoErrorNodeMap
//**************************************************************

pub type EarlyReturnOneToManyNoErrorNodeMap =
  fn(VXML) -> #(List(VXML), TrafficLight)

// *** without forbidden ***

fn early_return_one_to_many_no_error_nodemap_recursive_application(
  node: VXML,
  nodemap: EarlyReturnOneToManyNoErrorNodeMap,
) -> List(VXML) {
  let #(nodes, signal) = nodemap(node)
  case nodes, signal {
    _, GoBack -> nodes
    [], Continue -> nodes
    [T(_, _)], Continue -> nodes
    [V(_, _, _, children) as node], Continue -> {
      let children =
        children
        |> list.map(early_return_one_to_many_no_error_nodemap_recursive_application(_, nodemap))
        |> list.flatten
      [V(..node, children: children)]
    }
    _, Continue -> {
      // right now we don't like to see EarlyReturn nodemap
      // replacing itself by > 1 node and asking
      // us to continue at child level ()
      panic as "EarlyReturn recursive_application asked to Continue after node spit itself"
    }
  }
}

pub fn early_return_one_to_many_no_error_nodemap_2_desugarer_transform(
  nodemap: EarlyReturnOneToManyNoErrorNodeMap,
) -> DesugarerTransform {
  fn (vxml) {
    early_return_one_to_many_no_error_nodemap_recursive_application(vxml, nodemap)
    |> infra.get_root_with_desugaring_error
    |> result.map(add_no_warnings)
  }
}

// *** with forbidden ***

fn early_return_one_to_many_no_error_nodemap_recursive_application_with_forbidden(
  node: VXML,
  nodemap: EarlyReturnOneToManyNoErrorNodeMap,
  forbidden: List(String),
) -> List(VXML) {
  use <- on.true_false(
    infra.is_v_and_tag_is_one_of(node, forbidden),
    [node],
  )
  let #(nodes, signal) = nodemap(node)
  case nodes, signal {
    _, GoBack -> nodes
    [], Continue -> nodes
    [T(_, _)], Continue -> nodes
    [V(_, _, _, children) as node], Continue -> {
      let children =
        children
        |> list.map(early_return_one_to_many_no_error_nodemap_recursive_application_with_forbidden(_, nodemap, forbidden))
        |> list.flatten
      [V(..node, children: children)]
    }
    _, Continue -> {
      // right now we're not super in love with EarlyReturn (or more
      // generally self_first) nodemap replacing itself by > 1 node
      // and asking us to continue at child level
      panic as "EarlyReturn recursive_application asked to Continue after node spit itself"
    }
  }
}

pub fn early_return_one_to_many_no_error_nodemap_2_desugarer_transform_with_forbidden(
  nodemap: EarlyReturnOneToManyNoErrorNodeMap,
  forbidden: List(String),
) -> DesugarerTransform {
  use <- bad_tag_guard(forbidden)

  fn (vxml) {
    early_return_one_to_many_no_error_nodemap_recursive_application_with_forbidden(vxml, nodemap, forbidden)
    |> infra.get_root_with_desugaring_error
    |> result.map(add_no_warnings)
  }
}
