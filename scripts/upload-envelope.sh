#!/usr/bin/env bash
# Uploads the v1 result envelope to the configured Elyseum project
# (POST /api/v1/projects/{slug}/runs). The host deduplicates by run
# identity, so a single POST per job is idempotent across re-runs.
#
# Inputs (env):
#   ENVELOPE_PATH   - path to the v1 envelope JSON file (required)
#   SERVER_ORIGIN   - Elyseum server base URL (required)
#   PROJECT_SLUG    - project identifier slug (required)
#   INGEST_TOKEN    - project-scoped ingest token (required; never echoed)
#   STRICT_MODE     - "true" fails the Action on upload failure (default: warn)
#   GITHUB_OUTPUT   - step outputs file (optional)
#
# Exit codes:
#   0 - upload succeeded, or a failure was reported non-strictly (warned)
#   1 - misconfiguration (missing input / missing envelope), or an upload
#       failure when STRICT_MODE is "true"
set -euo pipefail

for var in ENVELOPE_PATH SERVER_ORIGIN PROJECT_SLUG INGEST_TOKEN; do
  if [ -z "${!var:-}" ]; then
    echo "::error::upload: $var is required but not set."
    exit 1
  fi
done

if [ ! -s "$ENVELOPE_PATH" ]; then
  echo "::error::upload: envelope file '$ENVELOPE_PATH' is missing or empty."
  exit 1
fi

# A trailing slash would double up in the URL path.
SERVER_ORIGIN="${SERVER_ORIGIN%/}"

# Bounded retry on transient failures only: curl's --retry covers timeouts
# and HTTP 408/429/500/502/503/504, --retry-connrefused adds a
# briefly-down server. Auth (401/403) and validation (422) failures are
# terminal and never retried.
RESPONSE_BODY="$(mktemp)"
trap 'rm -f "$RESPONSE_BODY"' EXIT

set +e
http_code=$(curl -s -o "$RESPONSE_BODY" -w '%{http_code}' \
  --max-time 30 \
  --retry 3 \
  --retry-delay 2 \
  --retry-connrefused \
  -X POST \
  -H "Authorization: Bearer $INGEST_TOKEN" \
  -H "Content-Type: application/json" \
  --data-binary "@$ENVELOPE_PATH" \
  "$SERVER_ORIGIN/api/v1/projects/$PROJECT_SLUG/runs")
curl_exit=$?
set -e

success=false
message=""

if [ "$curl_exit" -ne 0 ]; then
  message="Upload failed: could not reach $SERVER_ORIGIN (curl exit $curl_exit)."
elif [ "$http_code" = "201" ]; then
  success=true
elif [ "$http_code" = "200" ]; then
  success=true
  message="idempotent redelivery: the run already existed and was updated."
else
  # The 422 body carries the host's machine-readable validation error; a
  # truncated snippet makes the warning actionable. It never contains the
  # ingest token.
  body_snippet=""
  if [ -s "$RESPONSE_BODY" ]; then
    body_snippet=" Server said: $(head -c 300 "$RESPONSE_BODY" | tr -d '\r\n')."
  fi
  case "$http_code" in
    401 | 403) message="Upload rejected: authentication failed (HTTP $http_code). Check the ingest token." ;;
    404) message="Upload failed: project not found (HTTP 404). Check elyseum-project-slug." ;;
    413) message="Upload rejected: envelope exceeds the server's payload limit (HTTP 413)." ;;
    422) message="Upload rejected: envelope validation failed (HTTP 422).$body_snippet" ;;
    429) message="Upload rate-limited (HTTP 429). Retry later or reduce upload frequency." ;;
    5*) message="Elyseum server error (HTTP $http_code). Check the server's health." ;;
    *) message="Upload failed with unexpected HTTP $http_code." ;;
  esac
fi

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  {
    echo "uploaded=$success"
    echo "http_code=${http_code:-000}"
  } >> "$GITHUB_OUTPUT"
fi

if [ "$success" = "true" ]; then
  echo "Envelope uploaded (HTTP ${http_code:-000}).${message:+ $message}"
  exit 0
fi

if [ "$STRICT_MODE" = "true" ]; then
  echo "::error::$message"
  exit 1
fi

echo "::warning::$message"
exit 0
