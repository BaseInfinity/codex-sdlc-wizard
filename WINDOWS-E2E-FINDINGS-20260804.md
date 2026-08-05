# Windows Codex Desktop E2E — findings, 2026-08-04

Run of `WINDOWS-CODEX-DESKTOP-E2E.md` @ `04d8b94` against product repo `m180-jumpseat`.
Verdict: **PASS WITH FOLLOW-UP**. Sixteen defects below.

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

## 12. Managed-file hashes mistake Git EOL conversion for customization — HIGH

The update wrote `.codex/config.toml` and `.codex-sdlc/model-profile.json` with LF
line endings and recorded hashes of those LF bytes. After commit `3bf9956`, native
Windows Git kept LF in the index but materialized CRLF in the working tree because
the system configuration has `core.autocrlf=true` and the consumer repo had no
`.gitattributes` protection. Both paths remained Git-clean, but `check.sh` hashed
their raw working-tree bytes and reported them as `customized`.

Raw-byte evidence from `C:\Users\stefa\m180-jumpseat`:

| Managed file | Worktree bytes / CR count | Raw worktree SHA-256 | LF canonical bytes / SHA-256 |
|---|---:|---|---|
| `.codex/config.toml` | 116 / 7 | `68b0d71cc4d9145285fbff9af0d02d741529a869be49ebd8bee0c58c9d80d43f` | 109 / `38d92aee716039309cb7d3e8c3a2c79e6e1a10885d75747e45ea87b3c0cbf276` |
| `.codex-sdlc/model-profile.json` | 1955 / 36 | `96463ae6ba64664e44d31942903bb464ba18e6d9afd0369ffa8a9d249098490d` | 1919 / `e6281a2714a64dabd866607d0b4e296dd2d907a0c367b3e4b37fdf530a8fa977` |

Each file contained only CRLF pairs (no lone CR or lone LF). Normalizing CRLF to LF
reproduced the manifest's `expected_hash` exactly. `git ls-files --eol` reported
`i/lf w/crlf attr/` for both files, while the `3bf9956` blobs contained zero CR bytes.
This confirms line-ending conversion, not content customization.

**Fix:** canonicalize CRLF and lone CR to LF before hashing text managed files, retain
the raw hash separately for diagnostics, and migrate EOL-equivalent legacy manifest
hashes to the canonical value. Never canonicalize `.sh`: any CR byte in a managed
shell payload remains raw-byte drift and is classified broken. Setup and update also
merge the narrow `.codex/hooks/*.sh text eol=lf` rule into consumer `.gitattributes`,
preserving every existing consumer entry without imposing LF on unrelated shell files
or other managed content.

## 13. Proof runner sends PowerShell cmdlets to `cmd.exe` — HIGH

The m180 consumer manifest correctly records its PowerShell test command as:

    Invoke-Pester -Path tests

But `.codex/hooks/git-guard.cjs` reads that string from `scan` / `resolved_values`
and executes it with `childProcess.spawnSync(check, { shell: true })`. On Windows,
Node resolves that shell through `ComSpec`; the observed value is
`C:\WINDOWS\system32\cmd.exe`. `Invoke-Pester` is a function exported by the Pester
PowerShell module, not a standalone executable visible to `cmd.exe`.

The mandatory reviewed proof command therefore fails before running any test:

    Running SDLC proof check: Invoke-Pester -Path tests
    'Invoke-Pester' is not recognized as an internal or external command,
    operable program or batch file.
    SDLC proof check failed: Invoke-Pester -Path tests

PowerShell itself resolves the same command successfully as
`CommandType: Function`, `ModuleName: Pester`. This is not a missing-Pester or PATH
problem; the proof runner selected the wrong command interpreter.

**Impact:** every Windows PowerShell consumer whose manifest stores a PowerShell
cmdlet or function as its proof command is blocked at the mandatory commit/push proof
gate. m180 is a direct production-shaped reproduction. Changing an individual
consumer manifest or passing an ad hoc `--check` would only bypass the product defect.

**Fix:** make the proof runner execute PowerShell-repo proof commands inside an
explicit PowerShell host, for example
`pwsh -NoProfile -Command "Invoke-Pester -Path tests"`, while preserving the child
exit status. Add a Windows regression fixture whose manifest contains the bare
`Invoke-Pester -Path tests` command and assert that the proof runner selects `pwsh`,
runs the check, and writes a proof only after the check succeeds.

## 14. Update trusts an old consumer manifest instead of the invoked package — HIGH

The updated checker proved that m180's `.codex/hooks/git-guard.cjs` still matched its
consumer manifest, so `update.sh` classified it as `match -> keep`. But the file was
not current relative to the package performing the update:

| Source | SHA-256 |
|---|---|
| m180 consumer and its manifest | `3c2fb558edd07c82e1331106998d1c5c27bb9bbd122555ba23b5dd35e03bf705` |
| invoked wizard package | `be6172d293af10e2f469acb24a03ea25922206329241d1eedefb4e795bf1e785` |

The byte difference was the `79a00b9` Windows workspace-fingerprint repair that
normalizes the repository root with `path.resolve()`. Because consumer bytes still
matched their old recorded hash, the update never installed that fix. This affects
the normal case: an untouched managed file remains permanently pinned to whichever
package version first wrote its manifest entry.

**Impact:** hook and helper fixes can ship successfully yet never reach existing
consumers. A stale proof implementation may continue approving or rejecting commits
with already-fixed logic while update reports it healthy.

**Fix:** use a three-way decision for directly shipped managed artifacts: compare the
consumer's current hash with both its recorded manifest hash and the invoked package's
current hash. Upgrade when current still matches the old manifest but differs from the
package; preserve when current differs from both; and only refresh manifest ownership
when current already equals the package. Reuse canonical text hashes and raw `.sh`
hashes so line endings cannot disguise any of those relations.

## 15. Proof runner executes placeholder phrases as commands — HIGH

The m180 consumer manifest records `test_command` as `none configured`. The proof
runner's `safeProofCommand()` recognized only the exact tokens `none`, `n/a`, `unknown`,
and `<none>`, so the longer placeholder survived validation and was handed to the shell:

    Running SDLC proof check: none configured
    none: The term 'none' is not recognized as a name of a cmdlet
    SDLC proof check failed: none configured

**Impact:** a consumer with no configured proof commands is hard-blocked by an attempted
placeholder execution instead of receiving the actionable exit-2 guidance:

    No proof checks configured. Pass --check <command> or run setup first.

**Fix:** normalize candidate values for comparison by trimming, lowercasing, collapsing
internal whitespace, stripping paired angle brackets or quotes, and removing trailing
punctuation. Match only an explicit placeholder phrase set: `none`, `none configured`,
`not configured`, `none required`, `none needed`, `not applicable`, `n/a`, `na`,
`unknown`, `tbd`, `todo`, `no tests`, `-`, and `--`. Do not use prefix matching: a real
command such as `none-cli --version` must still execute. Regression fixtures prove both
that `none configured` reaches the existing no-checks path without executing a sentinel
and that `none-cli --version` remains a genuine command.

## 16. `Invoke-Pester` hides failed tests from the process exit code without `-EnableExit` — HIGH

Verified independently with Pester 5.7.1 and a one-test suite that deliberately fails.
This invocation reported `Tests Passed: 0, Failed: 1` but the `pwsh` process returned
exit code 0:

    Invoke-Pester -Path <failing-suite>

Running the same suite with `-EnableExit` reported the same failed test and returned exit
code 1:

    Invoke-Pester -Path <failing-suite> -EnableExit

This confirms the mechanism behind m180's proof run accepting a suite with 46 failures
and continuing to the next check: the proof runner correctly trusts the child process
status, but bare `Invoke-Pester` does not translate failed-test count into a failing
process status.

**Future fix (not implemented in the Defect 15 change):** ensure detected or generated
Pester proof commands opt into a failing process exit, using `-EnableExit` or the native
Pester 5 configuration equivalent. Add coverage that a failing Pester suite stops proof
execution before any later check. No Defect 16 product-code change was made in this
slice.
