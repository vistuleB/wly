# Client desugarer migration status

The maintained consumer projects now keep their project-specific desugarers
locally rather than in this repository:

- `courses`
- `dr`
- `little-bo-peep-solid`
- `ti2_html`

Each consumer can generate `src/local_desugarers.gleam`, renumber local blame
references, and run its local assertive tests through the maintenance API.

The remaining release work is package-level rather than consumer migration:

1. Preserve the constructor-owning compatibility API documented in
   `PUBLIC_API_BOUNDARY.md`.
2. Decide whether the Writerly adapter belongs in a small companion package or
   remains a published dependency of `vxml_pipeline`.
3. Replace the local Writerly path dependency before publication.
4. Audit public declarations so implementation helpers do not become an
   accidental permanent API.
5. Verify the maintained consumers against the release candidate.

The `ii2` project is defunct and is not part of the release compatibility set.
