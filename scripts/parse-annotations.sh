#!/usr/bin/env bash
# Parses the CLI reporter's annotations JSON into step outputs for the
# check run. Validates availability, JSON well-formedness, and the required
# keys; any violation prints an actionable ::error and exits 1.
set -euo pipefail

FILE="${1:?usage: parse-annotations.sh <annotations-json-path>}"

if ! command -v jq >/dev/null 2>&1; then
  echo "::error::jq is required to parse the annotations file but was not found on the runner."
  exit 1
fi

if [ ! -s "$FILE" ]; then
  echo "::error::Annotations file '$FILE' is missing or empty. Did the elyseum-cli reporter run successfully?"
  exit 1
fi

if ! jq -e . "$FILE" >/dev/null 2>&1; then
  echo "::error::Annotations file '$FILE' is not valid JSON."
  exit 1
fi

for key in name title summary status conclusion annotations; do
  if ! jq -e --arg k "$key" 'has($k)' "$FILE" >/dev/null; then
    echo "::error::Annotations file '$FILE' is missing the '$key' key."
    exit 1
  fi
done

{
  echo "annotations=$(jq -c '.annotations' "$FILE")"
  echo "name=$(jq -r '.name' "$FILE")"
  echo "title=$(jq -r '.title' "$FILE")"
  # Heredoc form keeps multi-line summaries intact in $GITHUB_OUTPUT.
  echo "summary<<__ELYSEUM_SUMMARY__"
  jq -r '.summary' "$FILE"
  echo "__ELYSEUM_SUMMARY__"
  echo "status=$(jq -r '.status' "$FILE")"
  echo "conclusion=$(jq -r '.conclusion' "$FILE")"
  # Ready-made JSON for checks-action's output (avoids shell interpolation).
  echo "check-output=$(jq -c '{summary: .summary}' "$FILE")"
} >> "$GITHUB_OUTPUT"
