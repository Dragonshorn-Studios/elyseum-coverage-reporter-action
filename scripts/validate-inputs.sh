#!/usr/bin/env bash
# Validates Action inputs before anything runs. Every failure prints an
# actionable ::error and exits 1.
set -euo pipefail

fail() {
  echo "::error::$1"
  exit 1
}

# Optional inputs default to empty under set -u; absence means "not given".
: "${ENVELOPE_TESTS_FORMAT:=}" "${ENVELOPE_TESTS_INPUT:=}" \
  "${ENVELOPE_COVERAGE_FORMAT:=}" "${ENVELOPE_COVERAGE_INPUT:=}" \
  "${PROJECT_SLUG:=}"

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

# Envelope adapter inputs are optional, but each format needs its report
# path and only known formats are accepted (matching the CLI's adapter
# registry, so callers get the error at the Action boundary).
check_pair() {
  local label="$1" format="$2" input="$3"
  if [ -z "$format" ] && [ -z "$input" ]; then
    return 0
  fi
  if [ -z "$format" ] || [ -z "$input" ]; then
    fail "$label-format and $label-input must be given together (only one is set)."
  fi
}
check_pair "envelope-tests" "$ENVELOPE_TESTS_FORMAT" "$ENVELOPE_TESTS_INPUT"
check_pair "envelope-coverage" "$ENVELOPE_COVERAGE_FORMAT" "$ENVELOPE_COVERAGE_INPUT"

case "$ENVELOPE_TESTS_FORMAT" in
  "" | vitest-json | junit | go-test-json) ;;
  *) fail "envelope-tests-format must be one of vitest-json, junit, go-test-json (got '$ENVELOPE_TESTS_FORMAT')." ;;
esac

case "$ENVELOPE_COVERAGE_FORMAT" in
  "" | lcov | clover | go-coverprofile) ;;
  *) fail "envelope-coverage-format must be one of lcov, clover, go-coverprofile (got '$ENVELOPE_COVERAGE_FORMAT')." ;;
esac

# Same slug grammar the host enforces (ProjectController rules); a bad slug
# here would otherwise surface as a confusing curl/404 failure at upload.
# Absence is fine (upload is opt-in); upload-envelope.sh requires it then.
slug="${PROJECT_SLUG:-}"
if [ -n "$slug" ] && ! [[ "$slug" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]; then
  fail "elyseum-project-slug must be lowercase alphanumerics separated by single hyphens (got '$slug')."
fi

exit 0
