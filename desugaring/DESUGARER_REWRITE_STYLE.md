# Desugarer rewrite style

This document describes the target style for mechanically cleaning up existing
desugarers. It is intended both for human contributors and for an AI continuing
the rewrite work.

The primary constraint is behavioral preservation. A style rewrite must not
change the public parameter shape, transformation behavior, warnings, errors,
blame provenance, or test meaning.

## File organization

Prefer this order:

1. Imports.
2. Nodemap callbacks and transformation helpers.
3. `inner_param_to_transform`.
4. `param_to_inner_param`.
5. Private `State`, `Param`, and `InnerParam` declarations.
6. `pub const name` and any blame helper.
7. Constructor documentation and `constructor`.
8. Assertive test data and `assertive_tests` at the bottom.

Keep tests at the bottom even when other declarations could technically follow
them.

## Public parameters and private implementation types

`Param` is the public calling shape used in pipeline modules. It must be built
from generic types such as tuples, lists, options, strings, integers, and
booleans. Do not make `Param` a desugarer-specific record: doing so would force
the pipeline module to import that record and its constructor.

Use formatter-resilient comments immediately before tuple fields:

```gleam
type Param =
  #(
    // Ancestor tags.
    List(String),
    // Replacement used inside a matching ancestor.
    #(String, String),
    // Replacement used outside a matching ancestor.
    #(String, String),
  )
```

Do not use horizontally aligned column comments. `gleam format` changes tuple
layout and destroys their alignment.

When rewriting an existing desugarer, convert every column-aligned tuple
comment into a comment immediately preceding its corresponding field. Preserve
all information from the original field documentation; change only its layout
and wording where needed for a readable standalone field comment.

`InnerParam` is private and should normally be a record when it contains
several semantically distinct values:

```gleam
type InnerParam {
  InnerParam(
    ancestor_tags: List(String),
    inside_from: String,
    inside_to: String,
    outside_from: String,
    outside_to: String,
  )
}
```

`param_to_inner_param` is the explicit boundary between the convenient public
calling shape and the named internal representation:

```gleam
fn param_to_inner_param(
  param: Param,
) -> Result(InnerParam, DesugaringError) {
  let #(ancestor_tags, inside, outside) = param
  let #(inside_from, inside_to) = inside
  let #(outside_from, outside_to) = outside

  Ok(InnerParam(
    ancestor_tags,
    inside_from,
    inside_to,
    outside_from,
    outside_to,
  ))
}
```

Use a type alias when `InnerParam` genuinely has the same simple meaning as
`Param`. Do not create a record merely to satisfy a rule.

## State

Private state with multiple semantic fields should normally be a record:

```gleam
type State {
  State(
    has_seen_ancestor: Bool,
    from: String,
    to: String,
  )
}
```

Prefer named access such as `state.from` over positional access such as
`state.1`. A scalar state, homogeneous collection, or self-evident pair may
remain a bare type or tuple.

## Nodemap callbacks

For enter/exit nodemaps, use the callback names established by
`nodemaps_2_transform`:

```text
on_enter
on_exit
on_text
```

Use `vxml` for a VXML argument rather than `node`. Preserve established local
conventions including `v_`, `t_`, `_val_`, and `TrafficLight`. Do not introduce
`_tag` suffixes merely to distinguish tag-related values. Keep plural grammar
correct—for example, `attrs` takes `have`, not `has`.

## Constructing the nodemap and transform

Rename `transform_factory` to `inner_param_to_transform`.

When nodemap construction is short and used only once, remove
`nodemap_factory` and construct a locally typed nodemap inside
`inner_param_to_transform`:

```gleam
fn inner_param_to_transform(
  inner: InnerParam,
) -> DesugarerTransform {
  let nodemap: n2t.OneToOneEnterExitStatefulNoErrorNodemap(State) =
    n2t.OneToOneEnterExitStatefulNoErrorNodemap(
      on_enter: fn(vxml, state) { on_enter(vxml, state, inner) },
      on_exit: on_exit,
      on_text: on_text,
    )

  let initial_state = State(
    has_seen_ancestor: False,
    from: inner.outside_from,
    to: inner.outside_to,
  )

  nodemap
  |> n2t.one_to_one_enter_exit_stateful_no_error_nodemap_2_desugarer_transform(
    initial_state,
  )
}
```

The explicit type annotation is important: it places the nodemap type beside
the corresponding `*_nodemap_2_desugarer_transform` adapter.

Keep a separate helper when constructing the nodemap involves substantial
logic, when it is reused, or when inlining would make
`inner_param_to_transform` difficult to scan.

## Constructor

The target concise form uses `desugaring/authoring`:

```gleam
pub fn constructor(param: Param) -> Desugarer {
  authoring.desugarer(
    name: name,
    param: param,
    prepare: param_to_inner_param,
    transform: inner_param_to_transform,
  )
}
```

This helper performs the same parameter inspection, validation-error capture,
and transform construction as the former explicit `Desugarer(...)` block.

Do not change the public `Param` while adopting this constructor form.

## Desugarer section decoration

The existing beach and wave section comments should remain. Remove obsolete lines
of this form when encountered:

```text
//------------------------------------------------53
```

Do not add replacement ruler lines.

## Assertive tests

Keep `assertive_tests_data` and `assertive_tests` at the bottom of the file.

Within every multiline `source` and `expected` VXML string, normalize the
minimum indentation of nonblank VXML lines to exactly 16 spaces. Move the block
as a whole: preserve every relative indentation level inside the VXML.

Target shape:

```gleam
source: "
                <> root
                  <> child
                    <>
                      'text'
                ",
expected: "
                <> root
                  <> renamed-child
                    <>
                      'text'
                ",
```

The test framework strips common leading indentation before parsing. The
16-space rule is solely for consistent source readability.

Incorrect normalization changes individual lines until they all have the same
indentation. Correct normalization shifts every line by the same amount so that
the least-indented nonblank VXML line begins at column 17.

Do not rewrite fixture content, quoting, or tree structure during indentation
normalization.

## Validation

Prefer validation owned by the defining library. For example, validate tags
with `vxml.validate_tag` when its structured error is useful. Boolean wrappers
such as `core.valid_tag` are acceptable when only a yes/no decision is needed.

Parameter validation belongs in `param_to_inner_param`; the nodemap should
normally receive prepared data.

## Mechanical procedure

For each desugarer:

1. Read the complete file and identify its public parameter shape and tests.
2. Rewrite types and comments without changing `Param` semantics.
3. Rename callbacks and `inner_param_to_transform` as appropriate.
4. Adopt the locally typed nodemap when it improves locality.
5. Adopt `authoring.desugarer` without changing constructor behavior.
6. Normalize VXML fixture blocks to a minimum indentation of 16 spaces.
7. Remove obsolete `//------------------------------------------------53` lines.
8. Run `gleam format` on the touched file.
9. Run `generate_desugarer_blames.sh` because formatting may shift blame lines.
10. Run the desugarer's focused assertive tests.
11. Run `gleam check`.
12. Periodically run the entire desugarer, Writerly, VXML, and consumer suites.

Keep behavioral changes, broad formatting passes, and style rewrites in
separate commits whenever possible.
