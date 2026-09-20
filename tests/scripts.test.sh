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

assert_output_contains() {
  local desc="$1" expected_code="$2" needle="$3"
  shift 3
  local out
  out="$(bash "$ROOT/scripts/parse-annotations.sh" "$1" 2>&1)"
  local code=$?
  if [ "$code" != "$expected_code" ] || [[ "$out" != *"$needle"* ]]; then
    echo "FAIL: $desc (expected exit $expected_code containing '$needle', got $code; output: $out)"
    FAILURES=$((FAILURES + 1))
  else
    echo "ok: $desc"
  fi
}

FIXTURES="$ROOT/tests/fixtures"

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
assert_output_contains "valid annotations parse" 0 "" "$FIXTURES/annotations-pass.json"
assert_output_contains "malformed JSON fails" 1 "not valid JSON" "$FIXTURES/annotations-malformed.json"
assert_output_contains "missing key fails" 1 "missing the 'conclusion' key" "$FIXTURES/annotations-missing-key.json"
assert_output_contains "empty file fails" 1 "missing or empty" "$FIXTURES/annotations-empty.json"

if [ "$FAILURES" -gt 0 ]; then
  echo "$FAILURES test(s) failed"
  exit 1
fi
echo "all script tests passed"
