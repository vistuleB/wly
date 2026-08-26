# Desugarer rewrite review queue

This file records source comments whose original column alignment or wording is
ambiguous enough to require later human confirmation. Rewriters should preserve
the apparent behavior and add an entry here rather than silently treating an
uncertain interpretation as authoritative.

## `add_between`

Original `Param` annotation:

```gleam
type Param = #(String,          String, String)
//             ↖                ↗       ↖
//             insert divs              tag name for
//             between adjacent         new element
//             siblings of these
//             two names
```

Interpretation used by the rewrite:

1. Tag of the first adjacent sibling.
2. Tag of the second adjacent sibling.
3. Tag of the element inserted between them.

The implementation agrees with this interpretation, but the crossed arrows and
shared first-two-field description should be confirmed by a human.

## Remaining top-down implementation ordering

### `lbp_img_build`

The public constructor and parameter preparation have been moved to the top,
but the 1,200-line implementation retains its existing internal organization.
It is divided by semantic comments around path handling, image metadata,
filesystem work, SVG processing, and traversal callbacks. Reordering those
sections mechanically would make the I/O-sensitive build logic harder to
review.

The banner and whitespace audit through
`filter_nodes_by_path_key_values_while_saving` found four large implementations
whose private functions are not yet consistently caller-before-callee:

- `counters_substitute_and_assign_handles`
- `dr_create_index`
- `dr_create_menu`
- `dr_generate_js_course`
- `fold_contents_into_text_if`
- `fold_custom_into_text`
- `fold_into_text`
- `fold_into_text__batch`
- `footnote_marker_to_sup_handle__outside`
- `grand_wrapper_append_attributes`
- `grand_wrapper_move_nodes_to_wrapper`
- `handles_generate_dictionary`
- `handles_generate_dictionary_and_id_list`
- `handles_generate_v_definitions_from_t_definitions`
- `handles_substitute`

These files contain substantial multi-pass implementations and semantic section
comments. Reorder each implementation as a dedicated pass so the comments move
with the functions they describe.

## `add_between_all_pairs_2`

Its original crossed-arrow `Param` annotation appears to mean: first list of
eligible left-sibling tags, second list of eligible right-sibling tags, and tag
of the inserted element. The implementation supports that reading. The `_2`
description says the second list should be smaller for efficiency; this agrees
with the short-circuit order of the two membership checks, but should be
confirmed by a human.
