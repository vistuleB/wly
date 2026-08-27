# Client desugarer migration

The migration must preserve the current workflow while consumer projects still
house their desugarers directly in this repository. Work is ordered so that
new facilities are additive before any existing workflow is changed.

## Migration sequence

1. Stabilize the compatibility API before moving definitions.
   - Keep the existing `desugaring/*` module paths supported.
   - Record which modules own public custom-type constructors in
     `PUBLIC_API_BOUNDARY.md`.
   - Do not use aliases as facades for constructor-owning types; Gleam aliases
     do not re-export constructors.
   - Keep all existing `desugaring/core` imports and desugarers working.
2. Add developer tooling alongside the current shell scripts.
   - Provide `blames`, `lint`, `generate-registry`, `new`, and `check` commands.
   - Require explicit target directories initially.
3. Test developer tools against copied fixtures.
   - Cover representative, malformed, and unconventional client desugarers.
   - Do not rewrite the live desugarer directory.
4. Adopt the tools in check-only mode inside `wly`.
   - Compare blame and registry results with the existing scripts.
   - Run lint informationally without modifying files or failing CI.
5. Make new generation mechanically equivalent to the existing scripts.
   - Review every intentional difference and eliminate nondeterminism.
6. Let one consumer opt in without relocating its desugarers.
   - Use the public testing facade and check-only tooling first.
7. Switch `wly` itself to the new tools.
   - Keep compatibility wrappers during the transition.
   - Commit mechanical migrations separately from behavioral changes.
8. Move client desugarers out of `wly`, one consumer at a time.
   - Establish the client registry and output equivalence before moving files.
   - Perform optional style cleanup only after relocation.
9. Deprecate old entry points after all known consumers have migrated.

## Design constraints

- Client desugarers remain ordinary Gleam modules.
- Constructor-owning public types remain in their compatibility modules until
  a deliberate breaking migration.
- Runtime authoring and testing APIs do not perform filesystem mutation.
- Source rewriting and inspection are explicit developer-tool operations.
- Check modes do not write files.
- Generated output is deterministic and carries a tool version.
- Structural requirements and optional house style produce distinct diagnostic
  levels.
