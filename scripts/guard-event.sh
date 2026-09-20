#!/usr/bin/env bash
# Guards unsupported event contexts: this Action publishes PR comments, so
# it requires github.event.pull_request.number. An empty number exits 1.
set -euo pipefail

PR_NUMBER="${PR_NUMBER:-}"

if [ -z "$PR_NUMBER" ]; then
  echo "::error::This action only supports pull_request events (github.event.pull_request.number is empty)."
  exit 1
fi

exit 0
