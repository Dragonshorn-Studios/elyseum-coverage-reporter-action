#!/usr/bin/env bash
# Unit tests for the Action's shell scripts. Plain bash asserts — this repo
# stays dependency-free. Run via: bash tests/scripts.test.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FAILURES=0

assert_exit() {
  local desc="$1" expected="$2"
  shift 2
  local out
  out="$(COMMAND="${1:-}" QUALITY_GATE="${2:-}" QUALITY_GATE_FAIL="${3:-}" WORKDIR="${4:-.}" bash "$ROOT/scripts/validate-inputs.sh" 2>&1)"
  local code=$?
  if [ "$code" != "$expected" ]; then
    echo "FAIL: $desc (expected exit $expected, got $code; output: $out)"
    FAILURES=$((FAILURES + 1))
  else
    echo "ok: $desc"
  fi
}

assert_parse() {
  local desc="$1" expected_code="$2" fixture="$3" needle="$4"
  : > "$OUTPUT_TMP"
  local out
  out="$(GITHUB_OUTPUT="$OUTPUT_TMP" bash "$ROOT/scripts/parse-annotations.sh" "$fixture" 2>&1)"
  local code=$?
  # The script writes key=value lines to $OUTPUT_TMP; read the actual file.
  local haystack
  haystack="$(cat "$OUTPUT_TMP" 2>/dev/null) $out"
  if ! printf '%s' "$haystack" | grep -qF "$needle"; then
    echo "FAIL: $desc (expected exit $expected_code with '$needle'; got exit $code, output: $haystack)"
    FAILURES=$((FAILURES + 1))
  else
    echo "ok: $desc"
  fi
}

FIXTURES="$ROOT/tests/fixtures"
OUTPUT_TMP="$(mktemp)"
trap 'rm -f "$OUTPUT_TMP"' EXIT

# The empty-file fixture is created here: git cannot track empty files.
: > "$FIXTURES/annotations-empty.json"

# GitHub runners ship jq; this dev machine may not. Skip jq-dependent tests
# when the tool is absent rather than reporting false failures.
# guard-event: empty PR number exits 1, number present exits 0
out="$(PR_NUMBER="" bash "$ROOT/scripts/guard-event.sh" 2>&1)"
code=$?
if [ "$code" != "1" ] || [[ "$out" != *"pull_request events"* ]]; then
  echo "FAIL: guard-event empty PR number (expected exit 1 with actionable error, got $code; $out)"
  FAILURES=$((FAILURES + 1))
else
  echo "ok: guard-event empty PR number"
fi

out="$(PR_NUMBER="42" bash "$ROOT/scripts/guard-event.sh" 2>&1)"
code=$?
if [ "$code" != "0" ]; then
  echo "FAIL: guard-event present PR number (expected exit 0, got $code; $out)"
  FAILURES=$((FAILURES + 1))
else
  echo "ok: guard-event present PR number"
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "skip: jq not installed; parse-annotations tests skipped"
  if [ "$FAILURES" -gt 0 ]; then
    echo "$FAILURES test(s) failed"
    exit 1
  fi
  echo "all non-jq script tests passed"
  exit 0
fi

# validate-inputs
assert_exit "valid inputs pass" 0 diff-coverage 80 15 .
assert_exit "unknown command fails" 1 deploy 80 15 .
assert_exit "non-numeric quality-gate fails" 1 diff-coverage eighty 15 .
assert_exit "non-numeric quality-gate-fail fails" 1 diff-coverage 80 15%
assert_exit "missing workdir fails" 1 diff-coverage 80 15 ./does-not-exist

# parse-annotations
assert_parse "valid annotations parse with all outputs" 0 "$FIXTURES/annotations-pass.json" "conclusion=failure"
assert_parse "malformed JSON fails with diagnostic" 1 "$FIXTURES/annotations-malformed.json" "not valid JSON"
assert_parse "missing key fails with diagnostic" 1 "$FIXTURES/annotations-missing-key.json" "missing the 'conclusion' key"
assert_parse "empty file fails with diagnostic" 1 "$FIXTURES/annotations-empty.json" "missing or empty"

if [ "$FAILURES" -gt 0 ]; then
  echo "$FAILURES test(s) failed"
  exit 1
fi
echo "all script tests passed"
