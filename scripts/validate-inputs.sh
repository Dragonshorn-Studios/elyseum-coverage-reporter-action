#!/usr/bin/env bash
# Validates Action inputs before anything runs. Every failure prints an
# actionable ::error and exits 1.
set -euo pipefail

fail() {
  echo "::error::$1"
  exit 1
}

# command: only the two commands that produce the PR comment/check-run files
# are supported; anything else is a caller mistake.
case "$COMMAND" in
  diff-coverage | coverage) ;;
  *) fail "Unsupported command '$COMMAND'. Supported: diff-coverage, coverage." ;;
esac

# Numeric thresholds: integers only (the CLI rejects everything else, but a
# clear message at the Action boundary is actionable).
for pair in "quality-gate:$QUALITY_GATE" "quality-gate-fail:$QUALITY_GATE_FAIL"; do
  name="${pair%%:*}"
  value="${pair#*:}"
  if ! [[ "$value" =~ ^[0-9]+$ ]]; then
    fail "$name must be a non-negative integer (got '$value')."
  fi
done

# workdir must exist before the CLI runs in it.
if [ ! -d "$WORKDIR" ]; then
  fail "workdir '$WORKDIR' does not exist."
fi

exit 0
