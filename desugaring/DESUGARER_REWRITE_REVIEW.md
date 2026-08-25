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
