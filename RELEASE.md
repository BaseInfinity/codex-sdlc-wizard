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

Run all of these and keep them green before tagging:

```bash
bash tests/test-release.sh
bash tests/test-roadmap.sh
bash tests/test-packaging.sh
bash tests/test-npm.sh
bash tests/test-skill.sh
bash tests/test-adapter.sh
bash tests/test-setup.sh
bash tests/test-update.sh
```

`bash tests/test-npm.sh` is required because it includes the packed tarball scratch smoke for:

- `npm pack`
- `codex-sdlc-wizard setup --yes`
- `codex-sdlc-wizard check`
- `codex-sdlc-wizard update check-only`

That smoke must stay clean on a fresh temp repo before release.

## 3. Optional High-Cost Proof

Run this when Codex auth is available and you want live CLI coverage before release:

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
