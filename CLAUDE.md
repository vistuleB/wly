# Writerly

NOTE : All paths mentioned at the top-level (outside section) are relative to the project root and all paths inside section that caters to library are relative to the library directory.

This is a Writerly (repo named `wly`) project.
Writerly has three libraries or applications written in Gleam.

1. `vxml`
2. `desugaring`
3. `writerly`

`Writerly` -> `VXML` -> `VXML` (through `Desugarer`) -> `OutputLine`

## VXML Library (directory `./vxml`)

`VXML` is an abstract syntax tree (AST) and an intermediary representation between `Writerly` and `OutputLine` that gets transformed by desugarers.


## Desugaring Library (directory `./desugaring`)

- All desugarers reside in `./src/desugarer` directory.
- Any new desugarer should be added in `./src/desugarer` directory.
- After each addition of a desugarer, 
  1. you **should** run `./desugaring/generate_desugarer_library.sh` script which will generate `./desugaring/src/desugarer_library.gleam`
  NOTE: `desugarer_library.gleam` is an interface to all desugarers that other projects uses.
  2. You **should** run test with `gleam run -m desugarers <desugarer_name>` from inside `./desugaring` library directory.
  NOTE: To test all desugarers, you can run `gleam run -m desugarers`
  
## Writerly Library (directory `./writerly`)

Writerly library convert `Writerly` syntax to `VXML`

## Dependencies

Each Gleam project has `gleam.toml` file that list dependencies. Local dependency has `path` attribute and 
the value is relative to the project. You can traverse the path relative to the library you are in to get 
to the dependent library.
