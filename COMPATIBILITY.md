# Compatibility matrix

What versions of the three Elyseum repositories work together, and who
owns which part of the contract.

| Component | Version | Contract role |
| --- | --- | --- |
| elyseum (host) | schema v1, MVP 05+ | **Owns** the canonical v1 envelope schema + fixture corpus (`schemas/envelope.v1.json`, `fixtures/envelope.v1/` + `MANIFEST.sha256`) |
| elyseum-cli | 1.0.12+ (pin via `elyseum-cli-version`) | Pins a copy of the schema + fixtures + manifest; CI fails on drift (`scripts/check-contract-drift.sh`). `emit-envelope` validates against the pinned schema before writing. |
| this Action | envelope-path contract | Never validates the envelope itself: it uploads the file the CLI emitted to the host's ingest endpoint. Coupled to the CLI only through the `elyseum-cli-version` pin. |

## Verified combinations

| Host schema | CLI | Action | Status |
| --- | --- | --- | --- |
| v1 (MVP 05) | 1.0.12 | @v1 (this) | supported |

## Release procedure (contract changes)

1. **Additive envelope change** (new optional fields): land in elyseum
   first with schema + fixtures + manifest; producers keep working.
2. **Breaking envelope change**: new major schema version directory
   (`schemas/envelope.v2.json`); v1 remains accepted for at least one
   release cycle of every producer.
3. Producers re-pin: CLI runs `scripts/sync-contract.sh` against the
   elyseum checkout carrying the release; the Action bumps
   `elyseum-cli-version`.
4. The host's drift check in each producer repo must pass in the same
   change-set as the re-pin (no silent half-migrates).
