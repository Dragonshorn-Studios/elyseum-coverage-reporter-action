#!/usr/bin/env bash
# Runs `elyseum-cli emit-envelope` for the upload path: maps the check-run
# conclusion onto the envelope's gate vocabulary, assembles the adapter
# flags, writes the CLI's exit code to $GITHUB_OUTPUT, and exits with it.
#
# Inputs (env):
#   ENVELOPE_PATH     - where the envelope is written (required)
#   CHECK_CONCLUSION  - check-run conclusion; success -> passed,
#                       failure -> failed, anything else -> unknown
#   TESTS_FORMAT / TESTS_INPUT       - optional adapter pair, given together
#   COVERAGE_FORMAT / COVERAGE_INPUT - optional adapter pair, given together
#   GITHUB_OUTPUT     - step outputs file (optional)
#
# Exit code: the CLI's exit code, verbatim (the Enforce step reports it).
set -euo pipefail

case "$CHECK_CONCLUSION" in
  success) gate_conclusion="passed" ;;
  failure) gate_conclusion="failed" ;;
  # neutral/timed_out/cancelled/... have no envelope equivalent; the host
  # records them as unknown rather than inventing a verdict.
  *) gate_conclusion="unknown" ;;
esac
args=(emit-envelope
  --emit-envelope.out "$ENVELOPE_PATH"
  --emit-envelope.quality-gate-conclusion "$gate_conclusion")
if [ -n "${TESTS_FORMAT:-}" ]; then
  args+=(--emit-envelope.tests-format "$TESTS_FORMAT" --emit-envelope.tests-input "$TESTS_INPUT")
fi
if [ -n "${COVERAGE_FORMAT:-}" ]; then
  args+=(--emit-envelope.coverage-format "$COVERAGE_FORMAT" --emit-envelope.coverage-input "$COVERAGE_INPUT")
fi
# set +e: the CLI's exit code is data for the Enforce step; re-exit with it.
set +e
elyseum-cli "${args[@]}"
cli_exit=$?
if [ -n "${GITHUB_OUTPUT:-}" ]; then
  echo "exit-code=$cli_exit" >> "$GITHUB_OUTPUT"
fi
exit "$cli_exit"
