# Prove It

This is the pre-commit proof gate.

## Minimum Questions

1. What changed?
2. What exact check proves it?
3. What command or action produced the proof?
4. What risk still remains?

## By Task Type

### Code changes

- Targeted test added or updated
- Test run completed
- Relevant command output captured

### Setup or environment repair

- Bootstrap or health check re-run
- Versions and paths confirmed
- Broken state is gone

### Auth or tenant work

- Correct account used
- Intended scopes requested
- Connection state confirmed

### Browser workflow

- Use Playwright or a manual browser check
- Capture the visible outcome

### Desktop-only workflow

- Run the desktop/manual validation
- Do not claim browser E2E covers it if it does not

## Commit Gate

Do not commit until you can answer:

- The failing state is real
- The passing state is real
- The proof is recent
- The diff matches the proof

After focused checks and self-review, run required broad verification through
the proof-stamping command for the git gate:

```bash
node .codex/hooks/git-guard.cjs prove --reviewed
```

For this repository, run and stamp the complete maintainer suite once with:

```bash
node .codex/hooks/git-guard.cjs prove --reviewed --check "node scripts/run-proof-suite.cjs"
```

Do not run `node scripts/run-proof-suite.cjs` immediately before this command;
the proof-stamping invocation already runs it.

If setup has not detected proof commands yet, pass them explicitly:

```bash
node .codex/hooks/git-guard.cjs prove --reviewed --check "npm test"
```

For Pester on every platform, include explicit failure propagation with `-EnableExit`
or Pester 5's `-CI` switch, such as `Invoke-Pester -Path tests -CI`. The proof
runner refuses an `Invoke-Pester` command without either switch so failed tests
cannot produce a passing proof stamp through a zero PowerShell process exit. The
switch must appear literally on `Invoke-Pester`; configuration-object and
splatted switch forms are intentionally rejected because the proof gate cannot
verify their runtime contents statically. Alias creation, background jobs, and
shell-wrapped PowerShell hosts are rejected for the same reason; invoke the
proof command directly in the proof host.

For a non-PowerShell project that previously stored a wrapper such as
`pwsh -File tests.ps1`, set `scan.language` in `.codex-sdlc/manifest.json` to
`"PowerShell"` and store the inner command directly, for example
`& ./tests.ps1`. Ensure the script
returns a nonzero process status when any test fails. The language applies to
every configured proof check, so consolidate a mixed shell/PowerShell set into
one PowerShell runner and clear the other proof-command fields; the runner must
fail if any delegated check fails.

The stamp is stored in Git metadata under `codex-sdlc/proof.json`, expires after
four hours, and is tied to the current worktree content so it does not dirty the
worktree. Guarded `git -C <path> commit` and `git -C <path> push` commands may
use fresh proof from a same-repository linked worktree because the guard verifies
the shared physical Git common directory. Unrelated repositories and other repo
context overrides such as `cd`, `--git-dir`, `--work-tree`, `GIT_DIR`, and
`GIT_WORK_TREE` remain blocked and require a session rooted in the target repo.
Inherited `GIT_NAMESPACE` and `GIT_OBJECT_DIRECTORY` are also blocked because
they retarget ref or object writes even when the worktree path is unchanged.
