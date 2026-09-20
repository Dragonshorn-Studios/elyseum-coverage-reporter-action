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
FAKE_BIN="$(mktemp -d)"
ENVELOPE_TMP="$(mktemp)"
CURL_LOG="$(mktemp)"
CLI_LOG="$(mktemp)"
trap 'rm -rf "$OUTPUT_TMP" "$FAKE_BIN" "$ENVELOPE_TMP" "$CURL_LOG" "$CLI_LOG"' EXIT

# The empty fixture is created at runtime so a fresh checkout always has
# it; .gitignore keeps it out of git status.
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

# upload-envelope: exercised through a fake curl on PATH, so the token,
# URL, and status handling are checked without any network traffic.
cp "$ROOT/tests/fake-bin/curl" "$FAKE_BIN/curl"
cp "$ROOT/tests/fake-bin/elyseum-cli" "$FAKE_BIN/elyseum-cli"
chmod +x "$FAKE_BIN/curl" "$FAKE_BIN/elyseum-cli"
printf '{"schema_version":"1"}' > "$ENVELOPE_TMP"
UPLOAD_TOKEN="ely_secret_token_123"

assert_upload() {
  local desc="$1" expected="$2" needle="$3"
  shift 3
  : > "$OUTPUT_TMP"
  : > "$CURL_LOG"
  local out kv
  # Overrides (VAR=value) are exported at runtime inside the subshell, on
  # top of the fixed defaults — expanded words are never treated as
  # assignment prefixes, so a plain inline form cannot express them.
  out="$(
    export PATH="$FAKE_BIN:$PATH" FAKE_CURL_LOG="$CURL_LOG" \
      ENVELOPE_PATH="$ENVELOPE_TMP" SERVER_ORIGIN="https://elyseum.example.com/" \
      PROJECT_SLUG="my-project" INGEST_TOKEN="$UPLOAD_TOKEN" STRICT_MODE=""
    for kv in "$@"; do export "$kv"; done
    bash "$ROOT/scripts/upload-envelope.sh" 2>&1
  )"
  local code=$?
  if [ "$code" != "$expected" ] || ! printf '%s' "$out" | grep -qF "$needle"; then
    echo "FAIL: $desc (expected exit $expected with '$needle'; got exit $code, output: $out)"
    FAILURES=$((FAILURES + 1))
  elif printf '%s' "$out" | grep -qF "$UPLOAD_TOKEN"; then
    echo "FAIL: $desc (ingest token leaked into script output)"
    FAILURES=$((FAILURES + 1))
  else
    echo "ok: $desc"
  fi
}

# Logs the recorded curl invocation with the token redacted, so failure
# output never trains the "token in logs" habit.
show_curl_log() {
  sed "s|$UPLOAD_TOKEN|[REDACTED]|g" "$CURL_LOG"
}

# Misconfiguration fails immediately — the guards exit before strict mode
# is even consulted.
assert_upload "missing envelope path fails" 1 "ENVELOPE_PATH is required but not set" \
  ENVELOPE_PATH="" FAKE_CURL_CODE=201
assert_upload "missing envelope file fails" 1 "is missing or empty" \
  ENVELOPE_PATH="./does-not-exist.json" FAKE_CURL_CODE=201

assert_upload "201 created succeeds" 0 "Envelope uploaded (HTTP 201)" FAKE_CURL_CODE=201
assert_upload "200 idempotent redelivery succeeds" 0 "idempotent redelivery" FAKE_CURL_CODE=200

assert_upload "401 warns in non-strict mode" 0 "::warning::Upload rejected: authentication failed" FAKE_CURL_CODE=401
assert_upload "401 fails in strict mode" 1 "::error::Upload rejected: authentication failed" \
  FAKE_CURL_CODE=401 STRICT_MODE=true

assert_upload "422 warning carries the server's validation snippet" 0 "schema-violation" \
  FAKE_CURL_CODE=422 FAKE_CURL_BODY='{"error":"envelope.schema-violation"}'

assert_upload "network failure warns in non-strict mode" 0 "could not reach" FAKE_CURL_FAIL=1
assert_upload "network failure fails in strict mode" 1 "could not reach" \
  FAKE_CURL_FAIL=1 STRICT_MODE=true

# The request itself: correct endpoint (trailing slash stripped from the
# origin), and the token travels only in the Authorization header.
assert_upload "request reaches the canonical ingest URL" 0 "Envelope uploaded" FAKE_CURL_CODE=201
if grep -qFx "https://elyseum.example.com/api/v1/projects/my-project/runs" "$CURL_LOG" &&
  grep -qFx "Authorization: Bearer $UPLOAD_TOKEN" "$CURL_LOG"; then
  echo "ok: curl call carries the ingest URL and bearer header"
else
  echo "FAIL: curl call carries the ingest URL and bearer header ($(show_curl_log))"
  FAILURES=$((FAILURES + 1))
fi

# The curl SLA contract: bounded timeout, bounded retries, and the
# envelope as the request body — dropping any of these changes behavior
# silently (unbounded hang, no retry, empty payload).
if grep -qFx -- "--max-time" "$CURL_LOG" && grep -qFx "30" "$CURL_LOG" &&
  grep -qFx -- "--retry" "$CURL_LOG" && grep -qFx "3" "$CURL_LOG" &&
  grep -qFx -- "--data-binary" "$CURL_LOG" && grep -qFx "@$ENVELOPE_TMP" "$CURL_LOG"; then
  echo "ok: curl call is bounded with the envelope as its body"
else
  echo "FAIL: curl call is bounded with the envelope as its body ($(show_curl_log))"
  FAILURES=$((FAILURES + 1))
fi

assert_upload "404 names the project slug as the suspect" 0 "project not found" FAKE_CURL_CODE=404
assert_upload "5xx reports a server error" 0 "Elyseum server error (HTTP 503)" FAKE_CURL_CODE=503

# emit-envelope: exercised through a fake elyseum-cli on PATH that records
# its argv, so the conclusion mapping and flag assembly are pinned.
check_cli_args() {
  local desc="$1"; shift
  local missing=0 arg
  for arg in "$@"; do
    if ! grep -qFx -- "$arg" "$CLI_LOG"; then
      missing=1
    fi
  done
  if [ "$missing" = "0" ]; then
    echo "ok: $desc"
  else
    echo "FAIL: $desc (argv: $(sed "s|$UPLOAD_TOKEN|[REDACTED]|g" "$CLI_LOG"))"
    FAILURES=$((FAILURES + 1))
  fi
}

run_emit() {
  local desc="$1" expected="$2" conclusion="$3"
  shift 3
  : > "$CLI_LOG"
  : > "$OUTPUT_TMP"
  local out kv
  out="$(
    export PATH="$FAKE_BIN:$PATH" FAKE_CLI_LOG="$CLI_LOG" GITHUB_OUTPUT="$OUTPUT_TMP" \
      ENVELOPE_PATH="envelope.json" CHECK_CONCLUSION="$conclusion" \
      TESTS_FORMAT="" TESTS_INPUT="" COVERAGE_FORMAT="" COVERAGE_INPUT="" FAKE_CLI_EXIT="0"
    for kv in "$@"; do export "$kv"; done
    bash "$ROOT/scripts/emit-envelope.sh" 2>&1
  )"
  EMIT_EXIT=$?
  EMIT_OUT="$out"
}

# Conclusion mapping: the only translation point between check-run
# vocabulary and the envelope's gate verdicts.
run_emit "success maps to passed" 0 success
check_cli_args "success maps to passed" "emit-envelope" "--emit-envelope.out" "envelope.json" \
  "--emit-envelope.quality-gate-conclusion" "passed"
run_emit "failure maps to failed" 0 failure
check_cli_args "failure maps to failed" "--emit-envelope.quality-gate-conclusion" "failed"
run_emit "other conclusions map to unknown" 0 neutral
check_cli_args "other conclusions map to unknown" "--emit-envelope.quality-gate-conclusion" "unknown"

# Adapter flags appear exactly when their format is given.
run_emit "no adapter flags when formats are empty" 0 success
if grep -qFx -- "--emit-envelope.tests-format" "$CLI_LOG" || grep -qFx -- "--emit-envelope.coverage-format" "$CLI_LOG"; then
  echo "FAIL: no adapter flags when formats are empty ($(cat "$CLI_LOG"))"
  FAILURES=$((FAILURES + 1))
else
  echo "ok: no adapter flags when formats are empty"
fi
run_emit "tests pair appended when given" 0 success TESTS_FORMAT=junit TESTS_INPUT=tests/junit.xml
check_cli_args "tests pair appended when given" \
  "--emit-envelope.tests-format" "junit" "--emit-envelope.tests-input" "tests/junit.xml"
run_emit "coverage pair appended when given" 0 success COVERAGE_FORMAT=clover COVERAGE_INPUT=coverage/clover.xml
check_cli_args "coverage pair appended when given" \
  "--emit-envelope.coverage-format" "clover" "--emit-envelope.coverage-input" "coverage/clover.xml"

# The CLI's exit code is propagated verbatim and reported as an output.
run_emit "CLI exit code propagates" 5 success FAKE_CLI_EXIT=5
if [ "$EMIT_EXIT" = "5" ] && grep -qFx "exit-code=5" "$OUTPUT_TMP"; then
  echo "ok: CLI exit code propagates to exit status and output"
else
  echo "FAIL: CLI exit code propagates to exit status and output (exit $EMIT_EXIT, output: $(cat "$OUTPUT_TMP"))"
  FAILURES=$((FAILURES + 1))
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

assert_adapter() {
  local desc="$1" expected="$2" tf="$3" ti="$4" cf="$5" ci="$6" slug="${7:-}"
  local out
  out="$(COMMAND=diff-coverage QUALITY_GATE=80 QUALITY_GATE_FAIL=15 WORKDIR=. \
    ENVELOPE_TESTS_FORMAT="$tf" ENVELOPE_TESTS_INPUT="$ti" \
    ENVELOPE_COVERAGE_FORMAT="$cf" ENVELOPE_COVERAGE_INPUT="$ci" \
    PROJECT_SLUG="$slug" \
    bash "$ROOT/scripts/validate-inputs.sh" 2>&1)"
  local code=$?
  if [ "$code" != "$expected" ]; then
    echo "FAIL: $desc (expected exit $expected, got $code; output: $out)"
    FAILURES=$((FAILURES + 1))
  else
    echo "ok: $desc"
  fi
}

assert_adapter "empty adapter inputs pass" 0 "" "" "" ""
assert_adapter "valid tests pair passes" 0 junit tests/junit.xml "" ""
assert_adapter "valid coverage pair passes" 0 "" "" clover coverage/clover.xml
assert_adapter "both valid pairs pass" 0 go-test-json tests/go.json lcov coverage/lcov.info
assert_adapter "tests format without input fails" 1 junit "" "" ""
assert_adapter "tests input without format fails" 1 "" tests/junit.xml "" ""
assert_adapter "coverage format without input fails" 1 "" "" clover ""
assert_adapter "coverage input without format fails" 1 "" "" "" coverage/clover.xml
assert_adapter "absent project slug passes" 0 "" "" "" "" ""
assert_adapter "well-formed project slug passes" 0 "" "" "" "" my-project
assert_adapter "malformed project slug fails" 1 "" "" "" "" "My Project"
assert_adapter "double-hyphen slug fails" 1 "" "" "" "" a--b

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
