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
  "${PROJECT_SLUG:=}" "${SERVER:=}" "${INGEST_TOKEN:=}" "${STRICT_MODE:=}"

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
# path. Unknown formats are NOT rejected here: the CLI's adapter registry
# owns the format list (its own error is explicit), and duplicating the
# list would block use-dev-elyseum-cli branches that add adapters.
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

# Same slug grammar the host enforces (ProjectController rules); a bad slug
# here would otherwise surface as a confusing curl or 404 failure at upload.
# Absence is fine (upload is opt-in); upload-envelope.sh requires it then.
if [ -n "$PROJECT_SLUG" ] && ! [[ "$PROJECT_SLUG" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]; then
  fail "elyseum-project-slug must be lowercase alphanumerics separated by single hyphens (got '$PROJECT_SLUG')."
fi

# Upload wiring must be all-or-nothing: an empty elyseum-server silently
# disables the whole feature, so a slug or token without a server (often a
# secret that failed to resolve) must fail loudly, and a server without
# its slug/token would only fail later at upload time.
if [ -z "$SERVER" ]; then
  if [ -n "$PROJECT_SLUG" ] || [ -n "$INGEST_TOKEN" ]; then
    fail "elyseum-project-slug/elyseum-ingest-token are set but elyseum-server is empty, so upload is disabled. Is the elyseum-server secret defined? Set it, or remove the other two."
  fi
else
  case "$SERVER" in
    http://* | https://*) ;;
    *) fail "elyseum-server must be an http(s) origin, e.g. https://elyseum.example.com (got '$SERVER')." ;;
  esac
  if [ -z "$PROJECT_SLUG" ] || [ -z "$INGEST_TOKEN" ]; then
    fail "elyseum-server is set: elyseum-project-slug and elyseum-ingest-token are required."
  fi
fi

# Anything but an exact true/false would silently mean non-strict.
case "$STRICT_MODE" in
  "" | true | false) ;;
  *) fail "elyseum-strict-upload must be 'true' or 'false' (got '$STRICT_MODE')." ;;
esac

exit 0
