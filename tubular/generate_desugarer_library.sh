#!/usr/bin/env bash
# Generates src/desugarer_library.gleam from the files in src/desugarers/
set -euo pipefail

SRC_DIR="src/desugarers"
OUT_FILE="src/desugarer_library.gleam"

# Build a newline-separated list of module names (strip '__'-prefixed and '.gleam')
MODULES=$(find "$SRC_DIR" -maxdepth 1 -type f -name '*.gleam' ! -name '__*' \
          -exec basename {} .gleam \; | sort)

# Write the file
{
  # imports
  echo "import infrastructure as infra"
  printf '%s\n' "$MODULES" | while IFS= read -r m; do
    echo "import desugarers/${m}"
  done
  echo

  # consts
  printf '%s\n' "$MODULES" | while IFS= read -r m; do
    echo "pub const ${m} = ${m}.constructor"
  done
  echo

  # assertive_tests
  echo "pub const assertive_tests : List(fn() -> infra.AssertiveTestCollection) = ["
  printf '%s\n' "$MODULES" | while IFS= read -r m; do
    echo "  ${m}.assertive_tests,"
  done
  echo "]"
} > "$OUT_FILE"

echo "Wrote $OUT_FILE with $(printf '%s\n' "$MODULES" | wc -l | tr -d ' ') desugarer(s)."