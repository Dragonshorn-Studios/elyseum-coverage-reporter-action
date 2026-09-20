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
  echo "summary=$(jq -j '.summary' "$FILE")"
  echo "status=$(jq -r '.status' "$FILE")"
  echo "conclusion=$(jq -r '.conclusion' "$FILE")"
} >> "$GITHUB_OUTPUT"
