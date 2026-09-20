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
| `quality-gate-fail` | `15` | Changed-line coverage at or below this fails the run (exit 1). |
| `elyseum-cli-version` | `1.0.12` | Pinned npm version of elyseum-cli. |
| `use-dev-elyseum-cli` | *(empty)* | Git ref of elyseum-cli to build from source instead (for CLI development). |

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
