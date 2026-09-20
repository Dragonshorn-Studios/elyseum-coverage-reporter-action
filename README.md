# Elyseum Coverage Reporter Action

A thin GitHub Action that runs a pinned version of
[`elyseum-cli`](https://github.com/Dragonshorn-Studios/elyseum-cli) against
your repository and publishes exactly one PR comment plus one quality-gate
check run. Part of the
[Elyseum](https://github.com/Dragonshorn-Studios/elyseum) suite.

The CLI is installed from npm at a pinned version (input
`elyseum-cli-version`, default `1.0.12`); the Action itself runs on Node 20.

## Inputs

| Input | Default | Description |
| --- | --- | --- |
| `github_token` | `${{ github.token }}` | GitHub API access token. |
| `github_token_actor` | `github-actions[bot]` | Login owning `github_token`; used to find the comment from earlier runs. Set to your GitHub App slug when using an App installation token. |
| `command` | `diff-coverage` | elyseum-cli command to run (`diff-coverage` or `coverage`). |
| `comment-name` | `Elyseum Coverage Reporter` | Identifying name of the PR comment. |
| `workdir` | `.` | Working directory for the CLI. |
| `result-file-path` | `coverage/github.pr.coverage.md` | Comment markdown produced by the CLI reporter. |
| `annotation-file-path` | `coverage/github.pr.annotations.json` | Check-run annotations JSON produced by the CLI reporter. |
| `quality-gate` | `80` | Changed-line coverage below this warns. |
| `quality-gate-fail` | `15` | Changed-line coverage strictly below this fails the run (exit 1). |
| `elyseum-cli-version` | `1.0.12` | Pinned npm version of elyseum-cli. |
| `use-dev-elyseum-cli` | *(empty)* | Git ref of elyseum-cli to build from source instead (for CLI development). |
| `elyseum-server` | *(empty)* | Elyseum server origin (e.g. `https://elyseum.example.com`). **Upload is disabled while empty.** |
| `elyseum-project-slug` | *(empty)* | Project slug on the Elyseum server (required for upload). |
| `elyseum-ingest-token` | *(empty)* | Project-scoped ingest token; pass it from GitHub Secrets (required for upload). |
| `elyseum-strict-upload` | `false` | When `true`, an upload or envelope-emission failure fails the run; otherwise it emits a `::warning` and the PR feedback still publishes. |
| `envelope-path` | `envelope.json` | Where the v1 result envelope is written (relative to `workdir`) before upload. |
| `envelope-tests-format` | *(empty)* | Test report format for the envelope: `vitest-json`, `junit`, or `go-test-json`. Requires `envelope-tests-input`. |
| `envelope-tests-input` | *(empty)* | Test report path. Requires `envelope-tests-format`. |
| `envelope-coverage-format` | *(empty)* | Coverage report format for the envelope: `lcov`, `clover`, or `go-coverprofile`. Requires `envelope-coverage-input`. |
| `envelope-coverage-input` | *(empty)* | Coverage report path. Requires `envelope-coverage-format`. Without it, the CLI's default `coverage/lcov.info` report is used. |

## Behavior

- Requires a `pull_request` event; other contexts fail before any comment
  is attempted.
- The CLI runs with `continue-on-error` so a quality-gate failure (exit 1)
  still publishes the comment and check run — the Action then fails with a
  `::error::Quality gate failed.` annotation.
- The comment is found by `github_token_actor` + `comment-name` and updated
  in place; re-running never duplicates it.
- The annotations JSON is validated (well-formed JSON, required keys)
  before the check run is created; a malformed or missing file fails with
  an actionable error instead of publishing an empty check run.

## Upload to Elyseum (optional)

Set `elyseum-server`, `elyseum-project-slug`, and `elyseum-ingest-token`
and the Action additionally emits the versioned v1 result envelope (via
`elyseum-cli emit-envelope`) and uploads it to
`POST {server}/api/v1/projects/{slug}/runs`, so the PR feedback and the
hosted history receive identical facts.

- **Idempotent within an attempt.** Within a project, the host keys a run
  on provider + run id + job + attempt. Retries of the same attempt
  converge on one stored run (HTTP 201 created, then 200 updated). A
  workflow re-run increments GitHub's attempt counter, so it is recorded
  as its own run — which is the history you want when attempt 2 goes
  green after attempt 1 failed.
- **Quality-gate failures still upload.** A failed gate is exactly the
  kind of fact hosted history exists to record; the gate verdict travels
  in the envelope (`passed` / `failed`, or `unknown` when the check-run
  conclusion maps to neither).
- **Bounded retry, terminal failures never retried.** curl retries only
  transient failures (timeouts, HTTP 408/429/500/502/503/504, connection
  refused) — one attempt plus three retries, 30 s per attempt.
  Authentication and validation rejections fail immediately with an
  HTTP-code-specific message.
- **Upload failure ≠ quality-gate failure.** By default an upload problem
  emits a `::warning` and the run's verdict is unchanged; with
  `elyseum-strict-upload: true` it fails the run. Misconfiguration
  (missing token/slug, missing envelope) always fails with an actionable
  error.
- **The token is never logged.** It travels only in the `Authorization`
  header; supply it from GitHub Secrets, e.g.
  `elyseum-ingest-token: ${{ secrets.ELYSIUM_INGEST_TOKEN }}`.
- **Envelopes need at least one fact source.** Give the emit step a test
  report, a coverage report, or both; with neither and no default
  `coverage/lcov.info`, emission fails and the upload is skipped (or
  fails, in strict mode).

### Upload example

```yaml
      - name: Run Elyseum Coverage Reporter
        uses: Dragonshorn-Studios/elyseum-coverage-reporter-action@v1
        with:
          command: diff-coverage
          elyseum-server: https://elyseum.example.com
          elyseum-project-slug: my-project
          elyseum-ingest-token: ${{ secrets.ELYSIUM_INGEST_TOKEN }}
          envelope-tests-format: vitest-json
          envelope-tests-input: coverage/vitest.json
          # envelope-coverage-format/input default to the CLI's LCOV report.
```

For projects without an LCOV report at the default path, pass
`envelope-coverage-format: clover` (+ `envelope-coverage-input`) or
`go-coverprofile` analogously.

## Required permissions

The consuming workflow needs:

```yaml
permissions:
  contents: read
  pull-requests: write
  checks: write
```

## Example

```yaml
name: Coverage Report

on:
  pull_request:
    types: [opened, synchronize, reopened]

permissions:
  contents: read
  pull-requests: write
  checks: write

jobs:
  coverage:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Run Elyseum Coverage Reporter
        uses: Dragonshorn-Studios/elyseum-coverage-reporter-action@v1
        with:
          github_token: ${{ secrets.GITHUB_TOKEN }}
          command: diff-coverage
          quality-gate: "80"
          quality-gate-fail: "15"

concurrency:
  group: elyseum-coverage-${{ github.event.pull_request.number }}
  cancel-in-progress: false
```

Examples always reference a release tag (`@v1`, or an immutable `@v1.2.3`) —
never `@main`.

## Release coupling

The Action installs the CLI version from the `elyseum-cli-version` input.
Bump it deliberately when the CLI publishes new reporter features; the
input accepts any exact npm version so teams can pin and upgrade on their
own schedule.

## Repository roles

| Repository | Role |
| --- | --- |
| [elyseum] | Host: users/projects/authz, ingest API, CI history UI. Source of truth for the versioned CI result envelope. |
| [elyseum-cli] | Producer CLI: reads local CI artifacts and emits the versioned envelope. |
| [elyseum-coverage-reporter-action] (this repo) | Thin GitHub Action wrapping the CLI; optional upload to Elyseum. |

[elyseum]: https://github.com/Dragonshorn-Studios/elyseum
[elyseum-cli]: https://github.com/Dragonshorn-Studios/elyseum-cli
[elyseum-coverage-reporter-action]: https://github.com/Dragonshorn-Studios/elyseum-coverage-reporter-action
