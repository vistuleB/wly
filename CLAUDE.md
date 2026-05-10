# Writerly

NOTE: All paths mentioned at the top-level (outside a section) are relative to the project root. All paths inside a section that caters to a library are relative to that library's directory.

This is a Writerly (repo named `wly`) project.
Writerly has three libraries written in Gleam.

1. `vxml`
2. `writerly`
3. `desugaring`

The overall data-flow pipeline is:

```
Writerly source files
      ↓  (assemble: directory tree → List(InputLine))
List(InputLine)
      ↓  (parse: List(InputLine) → VXML)
VXML (single root node)
      ↓  (pipeline: VXML → VXML, via a list of Desugarers)
VXML (transformed)
      ↓  (split: VXML → List(OutputFragment(d, VXML)))
List(OutputFragment)
      ↓  (emit: OutputFragment(d, VXML) → OutputFragment(d, List(OutputLine)))
List(OutputFragment(d, List(OutputLine)))
      ↓  (write + prettify)
Output files (HTML, JSX, …)
```

In code this is summarized as:
```
Writerly → VXML → VXML (through Pipeline of Desugarers) → List(OutputLine)
```

---

## VXML Library (directory `./vxml`)

### What is VXML?

VXML ("Verbose XML") is an abstract syntax tree (AST) and intermediary representation that sits between Writerly source and the final output format. A VXML tree is composed of two node types defined in `./src/vxml.gleam`:

```gleam
pub type VXML {
  V(blame: Blame, tag: String, attrs: List(Attr), children: List(VXML))
  T(blame: Blame, lines: List(Line))
}
```

- **`V` node** — an element node with a tag name, a list of attributes (`Attr`), and a list of child VXML nodes.
- **`T` node** — a text node holding a list of `Line` records.

Supporting types:

```gleam
pub type Attr { Attr(blame: Blame, key: String, val: String) }
pub type Line { Line(blame: Blame, content: String) }
```

Every node/attribute/line carries a `Blame` (see below).

### Source files in `./src/`

| File | Purpose |
|---|---|
| `blame.gleam` | `Blame` type & utilities |
| `io_lines.gleam` | `InputLine` / `OutputLine` types and file I/O helpers |
| `vxml.gleam` | Core VXML types, parser, serializers (VXML, HTML, JSX) |
| `xml_streamer.gleam` | Streaming XML parser utilities |

### The `Blame` Type

Every piece of data in the pipeline carries a `Blame` that records where it came from. Four variants exist:

```gleam
pub type Blame {
  Src(comments: List(String), path: String, line_no: Int, char_no: Int, proxy: Bool)
  Des(comments: List(String), name: String, line_no: Int)
  Ext(comments: List(String), name: String)
  NoBlame(comments: List(String))
}
```

- `Src` — originated from a source file (path + line + char number).
- `Des` — introduced by a desugarer (desugarer name + synthetic line number).
- `Ext` — introduced by an external/named source (e.g., an emitter function).
- `NoBlame` — no traceable origin.

### `InputLine` and `OutputLine`

Defined in `./src/io_lines.gleam`. Both carry a `Blame`, an indentation level (`indent: Int`), and a content string (`suffix: String`). `InputLine` comes from reading source files; `OutputLine` is produced during the emit stage.

### VXML Text Format

VXML has its own human-readable serialization (used for debugging). The caret `<>` introduces a V-node and quoted strings introduce T-node lines:

```
<> SomeTag
  attr1=value1
  attr2=value2
  <>
    "this is a text child"
  <> ChildTag
```

### Serialization functions in `vxml.gleam`

- `vxml_to_string` / `vxmls_to_string` — serialize to VXML text format.
- `vxml_to_html_output_lines` / `vxmls_to_html_output_lines` — serialize to HTML `OutputLine`s.
- `vxml_to_jsx_output_lines` / `vxmls_to_jsx_output_lines` — serialize to JSX `OutputLine`s.
- `parse_string` / `parse_file` / `parse_input_lines` — parse VXML text format back into `VXML`.
- `streaming_based_xml_parser` / `xmlm_based_html_parser` — parse real XML/HTML into `VXML`.

### Dependencies (`gleam.toml`)

`vxml` depends only on external packages: `gleam_stdlib`, `simplifile`, `on`, `xmlm`, `gleam_regexp`, `splitter`.

---

## Writerly Library (directory `./writerly`)

### What is Writerly?

Writerly is a human-friendly markup syntax (files use the `.wly` extension) that is a semantic superset of XML. It is inspired by [Elm-Markup](https://github.com/mdgriffith/elm-markup). The library converts Writerly source into VXML.

### Writerly Syntax at a glance

```
|> SomeTag
    attr1=value1
    attr2=value2

    A paragraph with one line.

    A second paragraph.

    |> ChildTag
        attr3=val3

    !! this is a comment line (ignored)

    ```python
    def fn(x):
        return x + 1
    ```
```

Key rules:

- `|> TagName` opens a tag node. Attributes immediately follow as `key=value` lines at the next indentation level.
- Parent-child relationships are **indentation-based** using **4-space** increments.
- Blank lines are first-class semantic elements (they become `WriterlyBlankLine` nodes in the VXML tree). Whether a blank line appears between two siblings can affect desugaring behavior.
- Lines starting with `!!` are comments and are discarded during parsing.
- Triple-backtick fences open a code block (becomes a `WriterlyCodeBlock` node).
- A line that does not parse as `key=value` and does not start with `|>` is a text line (paragraph).
- To start a text line with leading spaces, prefix with `\`.

### Multi-file documents

Writerly documents are designed to span multiple files:

```
./some_dir
  ├─ __parent.wly
  ├─ chapter1.wly
  └─ chapter2.wly
```

The assembler (`assemble_input_lines`) indents the contents of sibling files by 4 spaces and appends them (in lexicographic order) to `__parent.wly`. This recurses into subdirectories. Files and directories whose names start with `#` are commented-out and ignored.

### Writerly AST (`writerly.gleam`)

```gleam
pub type Writerly {
  BlankLine(blame: Blame)
  Paragraph(blame: Blame, lines: List(Line))
  Comment(blame: Blame, lines: List(Line))
  CodeBlock(blame: Blame, attrs: List(Attr), lines: List(Line))
  Tag(blame: Blame, name: String, attrs: List(Attr), children: List(Writerly))
}
```

### Key functions

| Function | Purpose |
|---|---|
| `assemble_input_lines(dir, path_selectors)` | Assembles a directory tree of `.wly` files into `List(InputLine)` |
| `assemble_and_parse(dir, path_selectors)` | Assembles + parses in one step → `List(Writerly)` |
| `parse_input_lines(lines)` | Parses `List(InputLine)` → `List(Writerly)` |
| `writerlys_to_vxmls(writerlys)` | Converts `List(Writerly)` → `List(VXML)` |
| `writerly_to_vxml(writerly)` | Converts a single `Writerly` → `VXML` |
| `vxml_to_writerlys(vxml)` | Round-trips VXML back to `List(Writerly)` |
| `writerlys_to_string(writerlys)` | Serializes `List(Writerly)` back to Writerly text |

Special VXML tags produced from Writerly:
- `WriterlyBlankLine` — a blank line in the source.
- `WriterlyCodeBlock` — a fenced code block.
- `WriterlyComment` — comment lines (rarely kept; typically deleted early in the pipeline).

### Dependencies (`gleam.toml`)

`writerly` depends on the local `vxml` library plus: `gleam_stdlib`, `simplifile`, `gleam_regexp`, `gleam_time`, `splitter`, `filepath`, `dirtree`, `on`.

---

## Desugaring Library (directory `./desugaring`)

The desugaring library is the engine that transforms VXML trees through a composable pipeline of *desugarers* and then drives the full render loop (assemble → parse → pipeline → split → emit → write → prettify).

### Core Concepts

#### `Desugarer`

A `Desugarer` (defined in `./src/infrastructure.gleam`) is the atomic unit of transformation:

```gleam
pub type DesugarerTransform =
  fn(VXML) -> Result(#(VXML, List(DesugaringWarning)), DesugaringError)

pub type Desugarer {
  Desugarer(
    name: String,
    stringified_param: Option(String),
    stringified_outside: Option(String),
    transform: DesugarerTransform,
  )
}
```

A desugarer takes a VXML root and returns either an error or a `(new_vxml, warnings)` pair.

#### `Pipeline`

```gleam
pub type Pipeline = List(Desugarer)
```

A pipeline is simply an ordered list of desugarers applied in sequence. Note: in the `dr` consumer project the type is still referred to as `Pipe` (a rename to `Pipeline` has not yet been propagated there).

#### `Renderer`

The top-level orchestration type is `Renderer` (defined in `./src/desugaring.gleam`). It wires together all stages:

```gleam
pub type Renderer(a, c, d, e, f, g, h) {
  Renderer(
    assembler:  Assembler(a),        // dir/file → List(InputLine)
    parser:     Parser(c),           // List(InputLine) → VXML
    pipeline:   Pipeline,            // VXML → VXML
    splitter:   Splitter(d, e),      // VXML → List(OutputFragment(d, VXML))
    emitter:    Emitter(d, f),       // OutputFragment(d, VXML) → OutputFragment(d, List(OutputLine))
    writer:     Writer(d, g),        // writes OutputFragment to disk
    prettifier: Prettifier(d, h),    // optional post-processing (e.g. prettier)
  )
}
```

Pre-built defaults are available:
- `default_writerly_assembler(path_selectors)` — loads a `.wly` directory tree.
- `default_writerly_parser(only_args)` — parses Writerly input lines into a single VXML root.
- `default_xml_parser` / `default_html_parser` — parses XML/HTML input.
- `stub_splitter(suffix)` — emits the whole tree as one fragment.
- `default_writerly_emitter` — converts VXML back to Writerly text output lines.
- `stub_html_emitter` / `stub_jsx_emitter` — wraps VXML children in a boilerplate HTML/JSX shell.
- `default_writer` — writes fragments to the output directory.
- `default_prettier_prettifier` / `empty_prettifier` — runs prettier or does nothing.

`run_renderer(renderer, parameters, options)` drives the full end-to-end pipeline.

### Source files in `./src/`

| File | Purpose |
|---|---|
| `desugaring.gleam` | `Renderer`, stage type aliases, CLI processing, `run_renderer` |
| `infrastructure.gleam` | `Desugarer`, `Pipeline`, `Blame`-aware list/string utilities, nodemap walker types |
| `nodemaps_2_desugarer_transforms.gleam` | Converts nodemap functions into `DesugarerTransform`s (the "walk" machinery) |
| `desugarer_library.gleam` | **Auto-generated** — re-exports all desugarers as `pub const`s + `assertive_tests` list |
| `selector_library.gleam` | **Auto-generated** — re-exports all selectors as `pub const`s |
| `prefabricated_pipelines.gleam` | Higher-level pipeline fragments (LaTeX math splitting, markdown links, italic/bold, …) |
| `assertive_testing.gleam` | Test runner for desugarer unit tests |
| `group_replacement_splitting.gleam` | Regex-based text splitting helpers used by desugarers |
| `table_and_co_printer.gleam` | Pretty-printing tables for debug output |
| `roman.gleam` | Roman numeral utilities |
| `prefabricated_pipelines.gleam` | Reusable multi-step pipeline sub-sequences |

### Desugarer Directory (`./src/desugarers/`)

All individual desugarers live here (one file per desugarer). There are ~160 desugarers covering operations such as:

- **Structural**: `rename`, `unwrap`, `wrap`, `delete`, `append`, `prepend`, `free_children`, …
- **Attribute manipulation**: `append_attribute`, `delete_attribute`, `rename_attributes`, `cut_paste_attribute_from_self_to_child`, …
- **Class manipulation**: `append_class`, `delete_class`, `substitute_class`, …
- **Text manipulation**: `concatenate_text_nodes`, `fold_contents_into_text`, `trim`, `find_replace__outside`, …
- **Grouping/splitting**: `group_consecutive_children__outside`, `pair`, `wrap_children`, …
- **Validation/checks**: `check_tags`, `check_proper_tokenization`, …
- **Counters & handles**: `substitute_counters`, `counters_substitute_and_assign_handles`, `handles_add_ids`, …

#### Desugarer file anatomy

Each desugarer file follows a consistent structure:

```gleam
// 1. Type aliases for the parameter
type Param = #(String, String)  // e.g., (old_tag, new_tag)
type InnerParam = Param

// 2. Nodemap function — maps a single VXML node
fn nodemap(vxml: VXML, inner: InnerParam) -> VXML { ... }

// 3. Nodemap factory and transform factory
fn nodemap_factory(inner: InnerParam) -> n2t.OneToOneNoErrorNodemap { ... }
fn transform_factory(inner: InnerParam) -> DesugarerTransform { ... }

// 4. Parameter validation
fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) { ... }

// 5. Public name constant
pub const name = "rename"

// 6. Public constructor  ← this is what desugarer_library.gleam re-exports
pub fn constructor(param: Param) -> Desugarer { ... }

// 7. Assertive tests
pub fn assertive_tests() -> AssertiveTestCollection { ... }
```

The `constructor` function is the public API. `desugarer_library.gleam` re-exports every constructor as a `pub const` so consumer projects can write:

```gleam
import desugarer_library as dl

dl.rename(#("OldTag", "NewTag"))
dl.delete("WriterlyComment")
dl.append_class(#("div", "my-class"))
```

#### Naming conventions

- Files ending in `__batch` accept a `List` of parameter tuples, applying the same logic to multiple targets in one pass.
- Files ending in `__outside` operate on nodes that are *outside* (not inside) certain subtrees.
- Files starting with `lbp_` or `ti2_` or `ii2_` or `dr_` are project-specific desugarers for particular consumer projects.

### Selectors Directory (`./src/selectors/`)

A `Selector` narrows which lines of the VXML serialization are shown in tracking/diff output:

```gleam
pub type Selector = fn(List(SLine)) -> List(SLine)
```

Currently two selectors exist: `all` (keeps every line) and `verbatim`.

### Nodemap Walker Types (`nodemaps_2_desugarer_transforms.gleam`)

Rather than writing recursive tree-walk logic directly, desugarers supply a *nodemap* — a function that handles one node — and the framework walks the tree. Many nodemap shapes exist (named after their arity/error/statefulness):

- `OneToOneNoErrorNodemap` — maps each node to exactly one node, cannot fail.
- `OneToOneNodemap` — maps each node to one node, can fail with `DesugaringError`.
- `OneToManyNoErrorNodemap` — maps each node to a list of nodes, cannot fail.
- `OneToManyNodemap` — maps each node to a list, can fail.
- `FancyOneToOne*` — receives additional context (ancestors, siblings) alongside the node.
- `*Stateful*` — carries an accumulator state through the walk.
- `*BeforeAndAfter*` — provides hooks both before and after children are processed.
- `EarlyReturn*` — can short-circuit the walk.

Each variant has a corresponding `*_2_desugarer_transform` function that wraps it into a full `DesugarerTransform`.

### Prefabricated Pipelines (`prefabricated_pipelines.gleam`)

Higher-order helpers that produce multi-step `Pipeline` sub-sequences:

- `create_mathblock_elements(parsed_delimiters, produced_delimiter)` — splits `$$…$$` / `\[…\]` / `\begin{align}…\end{align}` into `MathBlock` nodes.
- `create_math_elements(parsed, produced, backup)` — splits `$…$` / `\(…\)` into `Math` nodes.
- `barbaric_symmetric_delim_splitting(regex, ordinary, tag, forbidden)` — generic symmetric delimiter splitting (used for `_italic_` and `*bold*`).
- `asymmetric_delim_splitting(…)` — for asymmetric open/close delimiters.
- `annotated_backtick_splitting(tag, annotation_key, forbidden)` — splits `` `{annotation}`` patterns.
- `markdown_link_splitting(forbidden)` — splits `[text](url)` into `a` nodes.
- `splitting_empty_lines_cleanup()` — concatenates text nodes and removes leftover empty-line sentinels after a splitting pass.

### Adding a New Desugarer

1. Create `./src/desugarers/<your_desugarer_name>.gleam` following the anatomy above.
2. Run `./generate_desugarer_library.sh` (or `./generate_all.sh`) from inside the `desugaring` directory. This regenerates `./src/desugarer_library.gleam`.
3. Test it: from inside `./desugaring`, run:
   ```
   gleam run -m desugarers <your_desugarer_name>
   ```
   To run all desugarer tests:
   ```
   gleam run -m desugarers
   ```

`generate_all.sh` runs all three generation scripts:
- `generate_desugarer_library.sh` → `src/desugarer_library.gleam`
- `generate_selector_library.sh` → `src/selector_library.gleam`
- `generate_desugarer_blames.sh` → renumbers `desugarer_blame(N)` calls with correct line numbers inside `src/desugarers/`.

### CLI options (via `desugaring.gleam`)

`run_renderer` (and `process_command_line_arguments`) support a rich set of flags:

- `--input-dir` / `--output-dir` — source and destination paths.
- `--only <key=value>` — filter the document to subtrees matching an attribute.
- `--track <selector> [+N] [-N]` — show VXML diffs around specific pipeline steps.
- `--dump <steps>` — dump VXML at given pipeline step numbers.
- `--table` — print the pipeline steps table.
- `--times` — print profiling timings.
- `--verbose` — verbose output.
- `--prettier` — run prettier on output files.

### Dependencies (`gleam.toml`)

`desugaring` depends on the local `vxml` and `writerly` libraries, plus many external packages: `gleam_stdlib`, `gleam_regexp`, `shellout`, `simplifile`, `xmlm`, `argv`, `gleam_time`, `ansel`, `splitter`, `colours`, `input`, `gleam_json`, `gleam_crypto`, `filepath`, `gleam_erlang`, `dirtree`, `either_or`, `on`.

---

## Dependencies Between Libraries

```
vxml        (no local deps)
  ↑
writerly    (depends on vxml)
  ↑
desugaring  (depends on vxml + writerly)
```

Each library's `gleam.toml` lists local dependencies with a `path` attribute relative to that library's directory. For example in `desugaring/gleam.toml`:

```toml
[dependencies]
vxml     = { path = "../vxml" }
writerly = { path = "../writerly" }
```

---

## How a Consumer Project Uses These Libraries (`dr` as an example)

A consumer project (e.g., `../dr`) depends on `desugaring` (which transitively brings in `vxml` and `writerly`). The typical pattern in a consumer is:

### `src/pipeline.gleam`

Builds a `List(Desugarer)` (historically called `List(Pipe)` — `Pipe` is the old name for `Desugarer`, not yet renamed in `dr`):

```gleam
import desugarer_library as dl
import infrastructure as infra

pub fn pipeline() -> List(infra.Pipeline) {
  [
    dl.check_tags(#(allowed_tags, "pre-transformation")),
    dl.delete("WriterlyComment"),
    dl.rename__batch([#("Chapter", "div"), #("Section", "div")]),
    // ...
  ]
  |> list.flatten
  // Note: in dr the list is returned directly; infra.desugarers_2_pipeline
  // wraps Desugarers into DecoratedDesugarers for the Renderer
}
```

### `src/renderer.gleam`

Defines the `Splitter`, `Emitter`, and calls `ds.run_renderer`:

- The **splitter** walks the transformed VXML tree and produces one `OutputFragment` per output file (e.g., one HTML file per chapter/section).
- The **emitter** wraps each VXML fragment in the HTML boilerplate (`<!DOCTYPE html>`, `<head>`, `<body>`, …) and converts it to `List(OutputLine)` using `vxml.vxmls_to_html_output_lines`.
- The **writer** (`default_writer`) writes `OutputLine`s to disk.

### `src/main.gleam`

Entry point that parses CLI arguments with `ds.process_command_line_arguments`, builds the `Renderer`, and calls `renderer.render(amendments, course_dir)`.
