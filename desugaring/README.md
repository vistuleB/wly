# Desugaring

A collection of utilities for transforming [VXML](https://github.com/vistuleB/wly/tree/main/vxml) through composable VXML pipelines, then splitting and emitting the result as one or more target documents such as HTML or JSX.

The package is currently named `desugaring`, but its central abstraction is closer to a VXML pipeline: parse or assemble source material into VXML, run a sequence of `VXML -> VXML` transforms, split the transformed tree into output fragments, emit each fragment, and write the resulting files.

## Pipeline Model

The renderer in `src/desugaring.gleam` wires together these stages:

```text
source path
  -> Assembler
    -> List(InputLine)
  -> Parser
    -> VXML
  -> Filterer
    -> VXML
  -> Pipeline
    -> VXML
  -> Splitter
    -> List(OutputFragment(_, VXML))
  -> Emitter
    -> List(OutputFragment(_, List(OutputLine)))
  -> Writer
    -> output files
```

A `Pipeline` is a list of `Desugarer` values. Each desugarer is a named transformation over a VXML tree, with structured errors and warnings. Many desugarers are implemented as nodemaps: the desugarer supplies local node logic and the core nodemap-to-transform machinery performs the tree walk.

## Main Modules

- `desugaring` contains the renderer types, default parser/assembler/filterer/splitter/emitter/writer utilities, command-line option handling, tracking, dumping, and `run_renderer`.
- `desugaring/core` contains the `Desugarer` and `Pipeline` types, warning/error types, VXML helpers, and shared desugarer utilities.
- `desugaring/nodemaps_2_transform` contains the tree-walking machinery used by many desugarers.
- `desugaring/tracking` contains selector types, selection operations, and tracking-output rendering.
- `desugaring/line_wrapping` contains the blame-preserving line-wrapping engine.
- `desugaring/desugarers` is generated and re-exports desugarer constructors.
- `desugaring/pipelines` contains reusable groups of desugarers for common text-splitting patterns such as math delimiters, markdown links, and inline markup.
- `desugaring/writerly_defaults` contains Writerly adapter defaults for the generic renderer.

## Writerly Adapter

The renderer core is input-format-agnostic. Writerly-specific assembly, parsing, and emitting live in `desugaring/writerly_defaults`:

```gleam
import desugaring/writerly_defaults as wd

wd.default_writerly_assembler
wd.default_writerly_parser
wd.default_writerly_emitter
```

Those defaults adapt Writerly source trees to the same renderer stages used by XML, VXML, or other input formats.

## Smoke Test

`test/renderer_smoke.gleam` is the basic renderer smoke test. It reads `samples/smoke.xml`, parses it as XML-backed VXML, runs a small generic pipeline, emits JSX-like output, and writes to `build/renderer-smoke-output`.

Run it with:

```sh
gleam run -m renderer_smoke
```

Run a compile check with:

```sh
gleam check
```

## Local Desugarers

A consumer project can keep its own desugarers in `src/desugarers/`. The
generated local registry has the fixed path `src/local_desugarers.gleam`, so
imports are consistent across consumer projects:

```gleam
import desugaring/desugarers as dl
import local_desugarers as local_dl
```

Regenerate the local registry from the consumer project's Gleam root:

```sh
gleam run -m desugaring/generate_local_desugarers_dot_gleam
```

The generator exports each module's `constructor` and collects each module's
`assertive_tests`.

Renumber blame references after editing local desugarers:

```sh
gleam run -m desugaring/renumber_local_desugarer_blames
```

With a consumer-provided `src/local_desugarer_tests.gleam`, test all local
desugarers or one named desugarer:

```sh
gleam run -m local_desugarer_tests
gleam run -m local_desugarer_tests -- my_desugarer
```

## Current Boundaries

The package still contains both generic and project-specific desugarers. Files prefixed with names such as `ti2_`, `ii2_`, and `dr_` are project-specific and are expected to move or be separated later. The LBP desugarers have moved into their consumer project as the first client-owned desugarer pilot. The generated `desugaring/desugarers` module currently exports the remaining desugarers together, so package consumers should treat that surface as transitional.

The intended future shape is:

- generic VXML pipeline core,
- reusable generic desugarers,
- adapter modules for specific input formats such as Writerly,
- project-specific desugarers outside the core package.
