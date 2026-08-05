# Windows Codex Desktop E2E — findings, 2026-08-04

Run of `WINDOWS-CODEX-DESKTOP-E2E.md` @ `04d8b94` against product repo `m180-jumpseat`.
Verdict: **PASS WITH FOLLOW-UP**. Nine defects below.

## Environment

- Windows 10 Home 10.0.19045.6466 x64
- Codex Desktop 26.727.6591.0
- Codex CLI 0.130.0 -> 0.146.0 (upgraded mid-run, owner-authorised)
- Node v24.13.0, Git 2.53.0.windows.1
- Git Bash `C:\Program Files\Git\bin\bash.exe`, `uname -s` = `MINGW64_NT-10.0-19045`
- Wizard checkout `04d8b94`, release 0.7.35, adapter v1.73.0

## What ran

1. Wizard checkout was dirty and diverged (ahead 11 / behind 125). Cleaned
   non-destructively: `git worktree move` (not `remove --force` — `.tmp-integrate` held
   4 modified test files), untracked items moved to a sibling scratch folder, safety
   branch `rescue/pre-reset-20260804` @ `99b53bf`, then `git reset --hard origin/main`.
2. Phase 1 baseline captured read-only: 20 repo hashes, 16,563 Codex-home hashes.
   `git status` byte-identical before/after capture.
3. Plugin not installed (Public search empty, Personal tab empty) -> used the runbook's
   verified-package fallback. `npm pack` of the committed HEAD export, extracted outside
   both repos. Identity: **56/56 shipped files matched**, 11 `.sh` files with zero CR
   bytes. No `npx`, no `@latest`.
4. `node <verified-package>/bin/codex-sdlc-wizard.js update` (initialized repo).
5. `check`, Codex restart, Phase 4 verification, read-only `$sdlc`.
6. Phase 5 re-hash comparison: **PRESERVED**.

## Result

- `check`: `match 10, missing 0, customized 7, drift/broken 0`, exit 0
- Model migration worked:
  - `.codex/config.toml`: `gpt-5.5`/`xhigh` -> `gpt-5.6-sol`/`high` (+ `review_model`)
  - `model-profile.json`: `schema_version 2`, `mixed` -> `gpt-5.6-terra`
  - `selected_profile`: `maximum` preserved
  - A fresh chat now opens at 5.6 Sol / High automatically
- Pre-existing dirty file `tests/sdlc/ScriptLayerAuditDoc.Tests.ps1` byte-identical
  (`sha256 28cc08b2b68770165e2e387c01fea1efbe61461e4fcb78a84c5b5d050a19486f`)
- Repo changed: `.codex/config.toml`, `.codex-sdlc/model-profile.json`,
  `.codex-sdlc/manifest.json`. Nothing else.
- Codex home: `skills/feedback`, `skills/setup-wizard`, `skills/update-wizard` refreshed,
  each backed up to `backups/skills/*.bak.<ts>/`. Nothing removed.

---

## 1. Runbook does not say which `codex` binary governs the 0.144.0 gate — HIGH

Phase 1 step 7 says stop if Codex CLI < 0.144.0, but Windows has two: the Desktop-bundled
binary and a global npm shim, and the shim wins on PATH. Here: shim `0.130.0`, Desktop
package `26.727.6591.0`. No tiebreak given, so the run halts on a binary the plugin path
may never invoke.

**Fix:** state the floor applies to whatever `Get-Command codex` resolves to (that is what
the Phase 2 npm fallback executes); add a step to detect a shadowing global install.

## 2. Desktop-bundled `codex.exe` version is unobtainable but the report requires it — MEDIUM

`Program 'codex.exe' failed to run ... ResourceUnavailable` — Windows denies execution
under `C:\Program Files\WindowsApps\`. The MSIX package version is not a CLI version.
`Get-AppxPackage`'s module also failed to load.

**Fix:** document a supported way to read the bundled CLI version, or scope the report to
the PATH CLI only.

## 3. Cleanup steps assume `Remove-Item` works — MEDIUM

`Remove-Item` via the Codex shell was blocked by execution policy. Phase 5 step 7 would
strand artifacts.

**Fix:** specify `cmd /c del` / `cmd /c rmdir /s /q`, or probe execution policy in the
Phase 1 preflight beside the Git Bash check. **Workaround verified:** `cmd /c del`.

## 4. Pre-update repo pins a model the runbook forbids — MEDIUM (docs only)

Before the update, `.codex/config.toml` pinned `gpt-5.5`/`xhigh` and `maximum` resolved to
`gpt-5.5`/`xhigh`. Repo-local config overrides user-level `gpt-5.6-sol`, and the model
picker cannot override the repo pin — five attempts (chip menu, hover-verified click,
offset compensation, `/model` + keyboard, `/model` + click) all reverted to 5.5 Extra High.
The same interaction worked first try in a repo without the pin. So runbook line 20 is
unsatisfiable until the update that fixes it has run. **The update does migrate correctly.**

**Fix:** have Phase 1 read `.codex-sdlc/model-profile.json` before enforcing the model
contract; on conflict, run the update at the repo-pinned model and verify the post-update
driver. Phase 4 step 6 should distinguish expected post-update from pre-update values.

## 5. `PreToolUse` disabled -> commit/push guard not enforced — HIGH

All four hooks are approved/trusted with valid stored hashes, but the stored user hook
state marks this repo's `pre_tool_use` entry `enabled = false`. `SessionStart`,
`PreCompact`, `PostCompact` are active; `PreToolUse` is not. The git commit/push guard
advertised in `CODEX_ADAPTER_PLAN.md` as a hard `PreToolUse decision:block` is therefore
**not enforced**. `check` still reports those hook files as `match` because it only
verifies presence and hash, never activation. Written policy and enforced policy diverge.

**Fix:** surface hook *activation* state in `check.sh` / update. A hook whose file matches
but whose event is disabled should warn, not report `match`. Phase 4 step 2 should require
reading the enabled flag.

## 6. `$sdlc` still resolves to two entries after update — MEDIUM

Phase 4 step 3 requires exactly one. Actual, post-update:

| Entry | Scope | Source |
|---|---|---|
| `sdlc` | repo-specific: implementation, fixes, refactors, tests, release | repo skill |
| `sdlc` | generic: Codex planning, TDD, proof, self-review | **user-level** |

The old branded label `Codex Sdlc Wizard: Sdlc` is gone and the descriptions now differ,
but the count is still two, so the step fails as written.

**Fix:** either reconcile user-level `skills/sdlc` against the repo-scoped one during
update, or amend step 3 to mean "exactly one repository-scoped `$sdlc`" and require the
user-level entry to be reported rather than treated as a duplicate.

## 7. Legacy `setup-wizard` / `update-wizard` / `feedback` refreshed, not consolidated — MEDIUM

v0.7.35 consolidated the old four-skill layout into `skill-sources/*` plus a single
`skills/codex-sdlc-wizard/` (commit `e4d5182` "prevent nested skill discovery collisions").
The update instead **refreshed the three legacy user-level skills in place** (all three
CHANGED, `.bak` copies created) and never created `skills/codex-sdlc-wizard`. A machine
that had the old layout keeps the old surface indefinitely — the consolidation never
reaches it.

**Fix:** decide whether the legacy trio is supported or retired. If retired, migrate via
the documented recoverable legacy-skill cleanup. If supported, fix the runbook's
duplicate-skill language.

## 8. Baseline hash set misses paths the update touches — LOW

Two paths the update modified were outside the Phase 1 step 12/13 capture set:

- `.codex-sdlc/manifest.json` — modified by update, not in the installer-targeted list,
  so it had no baseline hash.
- `.codex/hooks/sdlc-prompt-check.sh` — a **retired** file the update **removed**. Step 12
  lists retired `.js` names but not this one, so the deletion was invisible.

A preservation comparison that cannot see a deletion cannot prove preservation.

**Fix:** add `manifest.json` and every retired name known to `remove-retired-files.cjs` to
the step 12/13 capture list; have Phase 5 explicitly report removals.

## 9. Docs still say `xhigh` after migration to `high` — LOW

Post-update, `SDLC.md` line 29, `SDLC-LOOP.md` line 9, `START-SDLC.md` line 14 still state
`xhigh` is the default, while config and the live session use `high`. These are classified
`customized`, so the wizard correctly did not rewrite them — but the docs now contradict
the shipped config.

**Fix:** warn when a customized managed document contains a model/effort string that no
longer matches the resolved profile. Do not auto-rewrite customized files.

---

## Note for non-Windows operators

Reading the Windows checkout through a Linux-side git bridge reported 15 modified files;
native Windows git reported 1. The other 14 were pure CRLF-vs-LF artifacts. A scratch clone
showed "252 dirty files" that collapsed to 0 under `git diff -w --ignore-cr-at-eol`. Do not
trust a non-Windows shell's `git status` for the Phase 1 step 5 cleanliness gate. The
runbook's existing raw-byte CR checks and CRLF->LF normalisation rules are correct.

## 10. Repo requires `TESTING.md` but never shipped one — HIGH

The SDLC pre-commit check aborts before staging:

    Stopped before step 1 because the required SDLC pre-commit check encountered
    an error: TESTING.md does not exist. Nothing was staged, committed, or pushed.

`.agents/skills/sdlc/SKILL.md` says to read `TESTING.md` and `ARCHITECTURE.md`
"when they exist and are relevant", but the pre-commit check treats a missing
`TESTING.md` as a hard error rather than a skip. Upstream `main` at `04d8b94`
ships no `TESTING.md`.

Relatedly `bash check.sh` here returns
`{"repo_state":"uninitialized","reason":"manifest_missing","managed_files":{}}` —
the wizard is not installed into itself, so it cannot dogfood its own drift
detection either.

**Fix:** ship a real `TESTING.md`, or make the pre-commit check skip a missing
one to match the skill's own "when they exist" wording.

## 11. Proof suite fails on Windows: MSYS path passed to Node — HIGH

`node scripts/run-proof-suite.cjs` cannot go green on Windows:

    PASS: package.json version matches the roadmap current-release state
    PASS: npm pack includes the CLI, installer, plugin manifest, skill runtime, and Windows E2E runbook
    PASS: local npm exec defaults to adaptive setup with universal Node hooks when automation passes
    PASS: local npm exec setup honors the model-profile flag
    PASS: default CLI updates initialized clones without an explicit subcommand
    PASS: packed tarball scratch smoke proves setup, check, and update on a clean repo
    FAIL: default interactive CLI did not hand off into plain Codex correctly

    Error: Cannot find module '/c/Users/stefa/codex-sdlc-wizard/tests/../package.json'
    Require stack:
    - C:\Users\stefa\codex-sdlc-wizard\[eval]
      code: 'MODULE_NOT_FOUND'
    Node.js v24.13.0
    exit: 1

An MSYS-style path (`/c/Users/...`) is handed to `node`, which resolves paths
natively on Windows and cannot find `/c/...`. Pre-existing: the only working-tree
changes at the time were two new markdown files.

Environment: Windows 10 10.0.19045.6466 x64, Node v24.13.0, Git 2.53.0.windows.1,
Git Bash MINGW64_NT-10.0-19045, repo at `04d8b94`.

**Fix:** convert MSYS paths to native Windows form before invoking `node`
(`cygpath -w` at the call site), or resolve `package.json` relative to
`__dirname` inside the eval'd script instead of from a shell-supplied path. Add
a Windows lane to CI so this is caught there rather than on a laptop.

**Combined impact with defect 10:** a Windows contributor hits the missing
`TESTING.md` error first; supply that and the mandatory proof suite then fails on
this path bug. There is no legitimate route to a commit from Windows today.
