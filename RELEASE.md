# Release Checklist

Use this checklist before tagging any `vX.Y.Z` release from this repo.

## 1. Sync To Latest Main First

Do not do release proof on stale local history.

```bash
git fetch origin
git checkout main
git pull --ff-only origin main
```

If the release work happened on a branch, rebase or merge onto current `origin/main` before you treat any proof as real:

```bash
git rebase origin/main
```

If the branch cannot be cleanly rebased or merged onto `origin/main`, stop and fix that before continuing.

## 2. Required Proof Suite

Preferred path: run the bounded parallel proof runner and keep every check green before tagging:

```bash
node scripts/run-proof-suite.cjs
```

Use the serial fallback when debugging one failure at a time:

```bash
node scripts/run-proof-suite.cjs --serial
```

The runner covers the full maintainer suite below, writes per-check logs to a temp directory, and exits non-zero if any check fails. If you need to run the suite manually, run all of these and keep them green before tagging:

```bash
bash tests/test-release.sh
bash tests/test-roadmap.sh
bash tests/test-packaging.sh
bash tests/test-npm.sh
bash tests/test-skill.sh
bash tests/test-adapter.sh
bash tests/test-setup.sh
bash tests/test-update.sh
bash tests/test-benchmark.sh
bash tests/test-e2e.sh
```

`bash tests/test-npm.sh` is required because it includes the packed tarball scratch smoke for:

- `npm pack`
- `codex-sdlc-wizard setup --yes`
- `codex-sdlc-wizard check`
- `codex-sdlc-wizard update check-only`

That smoke must stay clean on a fresh temp repo before release.

For setup/install or Codex-handoff changes, also run one real external repo smoke from a representative target repo, not just temp-fixture coverage. On Windows, do it from a real PowerShell session where `codex` resolves through the normal PATH / `codex.cmd` behavior.

Minimum expectation for that smoke:

- run from a representative repo such as `C:\Users\stefa\gamelist` or another real target repo
- verify `codex --version` works in that same PowerShell session
- run the published package entrypoint from that repo
- confirm the human path behaves as intended, not just the fixture path

## 3. Optional High-Cost Proof

`bash tests/test-e2e.sh` is included in the proof runner, but it skips unless live Codex E2E is explicitly enabled. Run this when Codex auth is available and you want live CLI coverage before release:

```bash
bash tests/test-e2e.sh
```

This is optional because it burns tokens and depends on local auth state.

## 4. Final Review

- Self-review the exact diff you are about to release.
- Make sure `package.json`, `README.md`, and `ROADMAP.md` agree on the release version and release story.
- Confirm the worktree is clean except for intentional release artifacts you will not commit.

## 5. Tag And Publish

Only after the sync and proof steps above are done:

```bash
git tag vX.Y.Z
git push origin vX.Y.Z
```

That tag is the release trigger. GitHub Actions publishes npm and creates the GitHub Release.
