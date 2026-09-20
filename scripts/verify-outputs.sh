#!/usr/bin/env bash
# Verifies the CLI produced the files the publish steps consume, and that
# the CLI exit code is one of the documented values (0 ok, 1 gate failed).
# Any drift fails with an actionable ::error before publishing.
set -euo pipefail

fail() {
  echo "::error::$1"
  exit 1
}

if [ ! -s "$WORKDIR/$RESULT_FILE_PATH" ]; then
  fail "Result file '$WORKDIR/$RESULT_FILE_PATH' is missing or empty (CLI exit code: $CLI_EXIT_CODE)."
fi

if [ ! -s "$WORKDIR/$ANNOTATION_FILE_PATH" ]; then
  fail "Annotations file '$WORKDIR/$ANNOTATION_FILE_PATH' is missing or empty (CLI exit code: $CLI_EXIT_CODE)."
fi

case "$CLI_EXIT_CODE" in
  0 | 1) ;;
  *) fail "elyseum-cli exited with undocumented code $CLI_EXIT_CODE (expected 0 or 1)." ;;
esac

exit 0
