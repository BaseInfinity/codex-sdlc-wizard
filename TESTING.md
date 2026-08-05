# Testing

How `codex-sdlc-wizard` is tested, and what you are expected to run before you
commit.

## Test shape

This repository is a Bash installer plus a small Node CLI. There is no test
framework and no runner dependency — every suite is a standalone Bash script
under `tests/` that counts `PASS` / `FAIL`, prints a summary line, and exits
non-zero on failure.

Two exceptions worth knowing:

- All of them set `set -euo pipefail` except `tests/test-adapter.sh`, which
  manages its own error handling.
- `tests/test-e2e.sh` is the only suite that also counts `SKIP`, and the only
  one that can exit successfully without printing a summary — when E2E is
  enabled but the `codex` CLI is unavailable, it exits early at its preflight.

The practical shape is **integration-heavy**. Because the product *is* file
mutation — writing hooks, merging config, migrating profiles, packing a
release — the tests that matter run the real scripts against real temporary
repositories and assert on the resulting files. Unit-style assertions exist,
but they are the minority and deliberately so. Do not add percentage coverage
targets; they would measure the wrong thing here.

## The suites

| Suite | Covers |
|---|---|
| `tests/test-adapter.sh` | Hook payload behaviour against real Codex hook shapes |
| `tests/test-setup.sh` | `setup.sh` — fresh install, collision preflight, generated docs |
| `tests/test-update.sh` | `update.sh` — selective update, customization preservation, profile migration |
| `tests/test-skill.sh` | Skill generation from `skill-sources/`, discovery collisions |
| `tests/test-packaging.sh` | Shipped-file manifest and packaged layout |
| `tests/test-npm.sh` | `npm pack` output and the `bin/` entrypoint |
| `tests/test-release.sh` | Release metadata and version consistency |
| `tests/test-roadmap.sh` | `ROADMAP.md` structure and invariants |
| `tests/test-benchmark.sh` | Benchmark CSV shape under `benchmarks/` |
| `tests/test-e2e.sh` | Real Codex CLI sessions — proves hooks actually fire |

Fixtures live in `tests/fixtures/`.

## Running them

Run the whole proof suite:

```bash
node scripts/run-proof-suite.cjs
```

It runs `git diff --check` plus all ten suites, with bounded parallelism
(default 4 jobs). Useful flags:

```bash
node scripts/run-proof-suite.cjs --list      # show checks without running
node scripts/run-proof-suite.cjs --serial    # one at a time, readable output
node scripts/run-proof-suite.cjs --jobs N    # tune concurrency
```

Run a single suite directly while iterating:

```bash
bash tests/test-update.sh
```

## The E2E suite is opt-in

`tests/test-e2e.sh` starts **real Codex CLI sessions**, which consume API
tokens. It is the only suite gated this way, and it skips itself by default:

```bash
CODEX_E2E=1 bash tests/test-e2e.sh                    # opt in
CODEX_E2E=1 CODEX_E2E_MODEL=gpt-5.6-sol bash tests/test-e2e.sh
```

Default model is `gpt-5.6-sol`. It requires the `codex` CLI installed and
authenticated, and it tolerates transport failures (DNS, websocket, stream
disconnects) by skipping rather than failing, so a flaky network does not
produce a false red.

Every other suite is offline and free — there is no reason not to run them.

## Manual verification

Two things the automated suites cannot cover:

- **`WINDOWS-CODEX-DESKTOP-E2E.md`** — the operator-driven runbook for a real
  installation into a real product repository through the Codex Desktop UI.
  Run it before a release that touches setup, update, hooks, or skills.
- **`bash check.sh`** — reports managed-file drift for whatever repository it is
  run in. Note that this repository is *not* self-initialized: running it here
  returns `{"repo_state": "uninitialized", "reason": "manifest_missing"}`, which
  is expected. Use it against a consumer repo that has the wizard installed.

## Requirements

- **Node >= 18** (`package.json` `engines`)
- **Bash** — on Windows this means **Git Bash** (MSYS/MINGW). A WSL `bash.exe`
  is not a substitute; it cannot consume the Windows package paths the scripts
  use.

## Line endings matter

`.gitattributes` pins `*.sh` to `eol=lf`. Shipped shell payloads must be
LF-only — a CRLF byte in a `.sh` file breaks it under Git Bash. If you are
inspecting this repository from a non-Windows shell against a Windows
checkout, note that `git status` there will report large numbers of spurious
modifications; confirm with `git diff -w --ignore-cr-at-eol` before believing
them.

## Before you commit

1. `node scripts/run-proof-suite.cjs` — green.
2. If you touched setup, update, hooks, or skills: run the Windows Desktop
   runbook against a real consumer repo, or say plainly in the PR that you did
   not.
3. Self-review the diff. Do not claim a review passed that you did not run.

Follow a failing observable first: write or identify the failing test, watch it
go red, make the smallest change that turns it green. For setup, authentication,
or environment repair work, the failing observable replaces an artificial unit
test — see `SDLC-LOOP.md` and `PROVE-IT.md`.
