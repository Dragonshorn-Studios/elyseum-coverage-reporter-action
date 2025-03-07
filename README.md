# Elyseum Coverage Reporter Action

This GitHub Action installs `elyseum-cli`, runs it, and comments on a pull request with the results. It can update an existing comment or create a new one if needed.

## Inputs

- `node-version`: Node.js version to use (default: `22`)
- `result-file-path`: Path to the resulting file generated by `elyseum-cli` (default: `coverage/coverage-diff.md`)
- `command`: Command to run `elyseum-cli` with (default: `diff-coverage`)
- `comment-name`: Name of the comment to update or create (default: `Elyseum Coverage Reporter`)

## Example Usage

```yaml
name: Coverage Report

on:
  pull_request:
    types: [opened, synchronize, reopened]

jobs:
  coverage:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v2

      - name: Run Elyseum Coverage Reporter
        uses: Dragonshorn-Studios/elyseum-coverage-reporter-action@main
        with:
          result-file-path: 'coverage/coverage-diff.md'
          command: 'diff-coverage'
          comment-name: 'Elyseum Coverage Reporter'
```

## License

This project is licensed under the MIT License.