# Windows Codex Desktop Real-Install E2E

This runbook lets Claude Desktop use computer control to drive Codex Desktop through an authorized real installation of Codex SDLC Wizard in an existing Windows product repository. It is both an adoption procedure and a black-box E2E test.

Do not use `codex-sdlc-wizard` itself as the target repository. This repository contains the runbook and wizard source; the target must be the separate product repository where SDLC guardrails should be installed.

## What to paste into Claude Desktop

Open Claude Desktop in a fresh session with computer use enabled, then paste exactly:

```text
Use computer control to operate Codex Desktop on this Windows machine. Read WINDOWS-CODEX-DESKTOP-E2E.md from the current codex-sdlc-wizard checkout and execute the complete runbook. The installation target is the separate product repository currently open in Codex Desktop. Do not install the wizard into its own source repository. Do not commit, push, tag, publish, deploy, or begin product implementation. Return the required evidence report when finished.
```

If Codex Desktop is not already open to the intended product repository, Claude must stop and ask for the target repository rather than guessing.

## Operating contract

- Use Claude Desktop only as the external computer-use operator. Perform the repository work through the visible Codex Desktop user interface.
- After the Phase 1 profile inspection, use GPT-5.6 Sol at `high` reasoning. If an initialized repository still pins an older driver or `xhigh`, the repository pin wins and cannot be overridden from the picker: use that pinned model only to run the verified update, then restart and enforce the migrated post-update profile in Phase 4.
- Preserve every existing source file, document, hook, configuration file, customization, and uncommitted change.
- Do not clean, stash, reset, discard, or commit existing work.
- Do not commit, push, tag, publish, deploy, or open a pull request during this run.
- Do not manually delete `.codex`, `.agents`, `.codex-sdlc`, `AGENTS.md`, or existing SDLC documents.
- Do not uninstall the plugin initially. Inspect the current state first.
- If a wizard defect occurs, gather exact evidence and stop the affected phase. Do not modify the cached plugin or wizard source to hide the failure.
- Never include secrets, tokens, private source contents, or customer data in the final report.
- Redact secrets, tokens, private source text, and customer data from every warning, error, transcript, and screenshot included in the report. Replace only sensitive values with `[REDACTED]` so the diagnostic shape remains useful.

## Phase 1: Establish the real target and baseline

1. Bring Codex Desktop to the foreground.
2. Report the repository name and absolute Windows path shown by Codex.
3. Stop if the selected target is the `codex-sdlc-wizard` source repository.
4. Confirm the selected directory is the intended real product repository.
5. Confirm the separate `codex-sdlc-wizard` checkout is at the intended committed candidate and has no modified, staged, or untracked files. Stop if it is dirty. Export its committed `HEAD` without changing the checkout: run `git -C "<wizard-checkout>" archive --format=zip --output="<temporary-directory>\wizard-head.zip" HEAD`, expand that archive outside both repositories, and record the expanded directory as `<verified-head-export>`. The repository's `.gitattributes` pins `*.sh` to LF for normal checkouts; the committed export additionally avoids treating a pre-existing CRLF working tree as candidate payload.
6. In Codex, run read-only inspection commands to record:
   - Windows version and architecture
   - Codex Desktop package version, plus the Codex CLI version and executable path returned by `Get-Command codex` and `codex --version`
   - whether another global npm shim or executable shadows the Desktop installation on `PATH`
   - the Desktop-bundled CLI version when it can be obtained without bypassing Windows security; WindowsApps may prevent direct execution, so record `bundled CLI version unavailable` and the exact redacted error when it cannot be executed. Do not fail the run merely because this separate bundled version is unavailable; the Desktop package version is not a substitute CLI version.
   - Node.js and Git versions
   - repository root, branch, and `git status --short --branch`
   - configured remotes without contacting or changing them
   - the expected Codex SDLC Wizard release version from `<verified-head-export>\package.json`
   - an exact canonical candidate-payload manifest for every shipped file selected by the committed export's `package.json` `files` plus automatically included `package.json`; derive the path list with `npm pack "<verified-head-export>" --dry-run --json` and sort paths ordinally. In the committed export and every plugin or extracted-package source being compared, inspect each shipped `.sh` file as raw bytes before hashing: stop if it contains any carriage-return byte (including CRLF), and hash accepted `.sh` bytes exactly unchanged. Git Bash requires LF-only shell payloads. For other UTF-8 text, normalize CRLF and lone CR to LF before SHA-256 hashing; hash binary bytes unchanged. For `.codex-plugin/plugin.json`, parse JSON, canonicalize only the platform-generated `+codex...` suffix out of the top-level `version`, recursively sort object keys, and serialize compact UTF-8 JSON before hashing in every compared source; still record and compare the visible full plugin version separately.
7. Stop before plugin or npm work if the PATH-resolved Codex CLI returned by `Get-Command codex` is older than `0.144.0` or Node.js is older than 18. Report the resolved executable and unsupported prerequisite; do not let an update mutate the repository first. The `0.144.0` floor applies to this resolved PATH Codex CLI because it is the CLI the Phase 2 npm fallback and its handoff invoke, even when a global npm shim shadows Codex Desktop. It does not apply to an inaccessible WindowsApps executable whose bundled version is unavailable.

Before continuing, run `Get-Command bash -ErrorAction SilentlyContinue`, `bash --version`, and `bash -lc 'uname -s'` in PowerShell. Continue only when `uname` identifies an MSYS, MINGW, or CYGWIN environment. A WSL launcher named `bash.exe` is not Git Bash and cannot safely consume the Windows package paths used here. If compatible Bash is unavailable on `PATH`, stop before plugin mutation or npm fallback and report that this adaptive E2E requires Git Bash.

8. Record whether these paths already exist:
   - `AGENTS.md`
   - `.codex/config.toml`
   - `.codex/hooks.json`
   - `.agents/skills/sdlc/SKILL.md`
   - `.codex-sdlc/`
   - `SDLC.md`
   - `TESTING.md`
   - `ARCHITECTURE.md`
9. If `.codex-sdlc/manifest.json` exists but is invalid JSON or lacks the expected manifest object, stop before plugin inspection, setup, or update. A broken manifest is neither initialized nor safely uninitialized, and setup can partially mutate the repository before failing.
10. If `.codex/hooks.json` exists, parse and validate it before any setup, update, plugin mutation, or fallback execution. Require a JSON object; when `hooks` exists, require it to be an object whose event values are arrays, whose entries contain `hooks` arrays, and whose hook entries are objects with string `command` values when present. If `.codex/hooks.json` is invalid, stop before setup or mutation. Do not let setup create documents before discovering malformed hook configuration.
11. Before enforcing or validating the model contract, read `.codex-sdlc/model-profile.json` and `.codex/config.toml`. If `.codex-sdlc/manifest.json` is valid, record the repository as initialized, its existing selected profile, and its pre-update driver and reasoning effort. An initialized update must preserve that selected profile unless the user separately authorizes migration. When the existing repo pin conflicts with the current consumer default, do not fight the picker: run the update under the preserved repo-pinned model, then verify the migrated post-update driver and effort separately in Phase 4.
12. If the repository is uninitialized, stop when any unconditional installer target already exists: `.codex-sdlc/model-profile.json`, `.codex/hooks/bash-guard.sh`, `.codex/hooks/session-start.sh`, `.codex/hooks/git-guard.cjs`, `.codex/hooks/session-start.cjs`, `.codex/hooks/compact-guard.cjs`, `.codex/hooks/git-guard.ps1`, `.codex/hooks/session-start.ps1`, `.codex/hooks/git-guard.js`, `.codex/hooks/session-start.js`, or `.codex/hooks/sdlc-prompt-check.sh`. The model-profile file is an unconditional destructive collision because setup rewrites it, while the `.js` names and `sdlc-prompt-check.sh` are retired targets that current setup removes. Perform this collision preflight before either the plugin path or npm fallback.
13. Hash every pre-existing modified or untracked path reported by Git, recursively hashing files inside dirty directories. Record deleted paths as absent. Also hash every pre-existing manifest-managed path and every pre-existing installer-targeted path named in steps 8 and 12, regardless of Git status; this explicitly includes `.codex-sdlc/manifest.json`, `.codex/hooks/sdlc-prompt-check.sh`, and all other retired names known to the candidate's `lib/remove-retired-files.cjs`. These include ignored wizard files that update may rewrite or remove. If every dirty, managed, retired, and installer-targeted path cannot be captured, stop rather than claim preservation from Git status alone.
14. Resolve the active Codex home (normally `%USERPROFILE%\.codex`) and record existence plus recursive file hashes—never file contents—for its `skills\feedback`, `skills\setup-wizard`, `skills\update-wizard`, `skills\sdlc`, `skills\codex-sdlc`, `skills\codex-sdlc-wizard`, `backups\skills`, and `skill-backups` paths. The last two backup locations are distinct. `feedback`, `setup-wizard`, and `update-wizard` are supported global helper skills and are expected to be refreshed with recoverable backups. The `codex-sdlc-wizard` installer skill is plugin-owned and must not be copied into global `skills\codex-sdlc-wizard`; report a pre-existing standalone copy as legacy and preserve it unless the user authorizes the documented cleanup. These user-level mutations and legacy-installer migrations do not appear in repository Git status.
15. Preserve the complete baseline output for the final comparison.

## Phase 2: Inspect the plugin before changing it

1. Open Codex Desktop's Plugins interface.
2. Inspect both **Personal** and **Installed**.
3. Find **Codex SDLC Wizard** and record:
   - exact plugin version
   - installed/enabled state
   - whether duplicate plugin or installer entries appear
4. If the plugin is visible but not installed, use **Install**. If it is installed but disabled or not enabled, use **Enable**.
5. Compare the plugin's release version with the expected version recorded from this checkout's `package.json`, but do not treat a version-only match as candidate identity.
6. If the interface offers an Update or Reinstall action for an older or mismatched version, use that action and verify the version again.
7. Only uninstall and reinstall the plugin package when no in-place update path exists. Do not remove repository-local guardrails as part of a plugin reinstall.
8. If duplicate legacy installer skills appear, record their labels and scopes. Use only the wizard's documented recoverable legacy-skill cleanup; do not delete repository data.
9. Start a fresh Codex session after any plugin installation, enablement, update, reinstall, or legacy-skill cleanup.
10. Resolve the active installer skill's source path from Codex's visible work log and derive its native Windows plugin root. Convert it for Git Bash with `bash -lc 'cygpath -u "$1"' -- "<native-plugin-root>"` and record the result as `<verified-plugin-root>`. Recompute the complete canonical payload manifest using the exact Phase 1 path list and normalization rules. Every shipped payload path and hash must match before the plugin path can mutate the target; missing or extra expected payload files fail identity. A matching release-version label or `+codex...` build suffix alone is insufficient.

If the plugin is unavailable through the visible interface, or its exact payload manifest remains stale/mismatched after the supported update or reinstall path, use the exact committed `HEAD` export prepared in Phase 1 as the candidate fallback instead of resolving a registry dist-tag or packing potentially CRLF-converted working-tree files. Confirm that the Phase 1 Git Bash compatibility preflight passed, then run `npm pack "<verified-head-export>" --pack-destination "<temporary-directory>"` and extract that tarball outside both repositories. Do not use `@latest` for this candidate test. Recompute the complete canonical payload manifest for the extracted package using the Phase 1 path list and normalization rules. Every payload hash and the package version must match before execution. If either comparison differs, stop because neither available path can validate the intended candidate.

Execute the already verified extracted package directly; do not use `npx` after verification because it can resolve a different dist-tag or cached package. Choose the command from repository state, substituting the absolute extracted-package path for `<verified-package>`:

- Initialized repository (a valid `.codex-sdlc/manifest.json` exists): `node "<verified-package>\bin\codex-sdlc-wizard.js" update`
- Uninitialized repository: `node "<verified-package>\bin\codex-sdlc-wizard.js" setup --yes --model-profile maximum`

For an initialized repository with a pre-update model conflict recorded in Phase 1, run this update under the preserved repo-pinned model; do not claim the current model contract is active until the update finishes and a restarted session verifies the post-update configuration.

Do not install the npm package globally. Record that the verified-package fallback was required. When the selected command finishes, run `node "<verified-package>\bin\codex-sdlc-wizard.js" check` and capture the result. Keep the verified package through Phase 4 so the same trusted check command remains available, and remove its temporary directory only after the preservation comparison in Phase 5. Restart Codex Desktop in the same target repository, skip Phase 3, and continue with Phase 4. This npm fallback performs the repo operation directly and does not make the plugin-only `$codex-sdlc-wizard` installer entry available.

## Phase 3: Install or repair the real product repository

Skip this phase when the npm fallback completed successfully; it already performed the repository setup. This phase is only for the plugin UI path.

1. Reopen the target product repository in Codex Desktop.
2. Inspect `.codex-sdlc/manifest.json` and the existing `.codex/hooks/` scripts before mutation.
3. Search for `$codex-sdlc-wizard` and select **Install SDLC Guardrails**.
4. Give Codex this instruction, replacing `<verified-plugin-root>` with the exact plugin root fingerprinted in Phase 2:

   ```text
   Install or repair Codex SDLC guardrails in this repository using only the verified plugin payload. If the repository is initialized, preserve its existing selected profile and run exactly `bash "<verified-plugin-root>/update.sh"`. If it is uninitialized, confirm the Phase 1 collision preflight passed and run exactly `bash "<verified-plugin-root>/setup.sh" --yes --model-profile maximum`. After either operation, run exactly `bash "<verified-plugin-root>/check.sh"`. Do not use npx or any other package copy. Preserve every existing customization, document, hook, configuration file, application file, and uncommitted change. Do not commit or push.
   ```

5. Allow the selected bundled setup/update/check workflow to finish.
6. Do not substitute raw package edits or manual generated-file changes for a failed installer step.
7. Capture all visible output, warnings, approval requests, exit codes, created-file counts, and verification results.
8. If the operation recommends a restart, fully restart Codex Desktop or start a fresh session rooted in the same repository.

## Phase 4: Verify the installed workflow

1. Confirm Codex reopens the target repository without a hook, configuration, locale, or startup error.
2. Open `/hooks`. Review any pending repository hooks and confirm the wizard hooks are approved and active before relying on enforcement or declaring the install ready. Inspect the stored enabled state as well as approval/trust: require the repository `PreToolUse` event to be explicitly enabled, and treat `enabled = false` or a wizard-check `hook_activation.disabled_events` entry as a warning that commit/push enforcement is not ready. Approval alone is insufficient.
3. Confirm exactly one repo-scoped `$sdlc` appears for the target repository. Report and preserve any separate user-owned global `$sdlc`; do not count it as a second repository-scoped entry and do not delete or rewrite it without permission. Also confirm the supported global helper skills `feedback`, `setup-wizard`, and `update-wizard` are expected user-level entries, while `codex-sdlc-wizard` remains plugin-owned rather than copied into the global skills directory.
4. Invoke `$sdlc` with this read-only request:

   ```text
   Inspect the installed SDLC configuration and explain the active model profile, planning policy, TDD requirements, verification requirements, review gates, and commit/push rules. Cite the repo files that define each rule. Do not edit files and do not claim that any review has already passed.
   ```

5. Run the bundled wizard check from the same verified source used for mutation and capture its complete structured result: `bash "<verified-plugin-root>/check.sh"` for the plugin path, or `node "<verified-package>\bin\codex-sdlc-wizard.js" check` for the verified-package fallback.
6. Confirm all of the following:
   - repository state is initialized
   - an uninitialized installation selected `maximum`; an initialized update preserved the selected profile recorded in Phase 1
   - pre-update model values remain historical evidence only; after the update and restart, the driver matches the preserved/selected profile: `maximum` uses `gpt-5.6-sol` at `high`; an explicitly preserved `mixed` profile uses `gpt-5.6-terra` at `medium` with `gpt-5.6-sol` review explicitly set to `high`
   - required managed artifacts are present
   - no managed artifact is missing or drifted/broken
   - existing customizations are preserved according to the complete baseline comparison; preserved files may report as `match` when first recorded in a new manifest, while `customized` is reserved for drift from an existing manifest
   - there is no duplicate legacy `$codex-sdlc` or duplicate wizard installer entry
   - the post-install Git status contains only intentional wizard installation changes plus the exact pre-existing changes

## Phase 5: Preservation comparison

1. Re-run the baseline Git status and file hashes.
2. Compare every pre-existing modified/untracked path against the baseline.
3. Compare the recorded Codex-home skill and backup paths, and disclose every user-level skill replacement, backup, migration, or removal.
4. Explain every new, changed, or removed wizard-managed path, including deletion of any retired file captured from `lib/remove-retired-files.cjs`.
5. Treat an unexplained change to application code, an existing customization, or a user-level Codex skill as a failure.
6. Do not repair a preservation failure locally. Preserve evidence for the upstream issue.
7. After all comparisons and evidence capture finish, remove only the exact temporary verified-package files and extraction directory outside the target repository. If PowerShell `Remove-Item` is blocked, use Windows-native cleanup with explicit resolved paths: `cmd /c del /f /q "<temporary-package-file>"` for files and `cmd /c rmdir /s /q "<temporary-extraction-directory>"` for directories. Verify each target is the previously recorded temporary path and is outside both repositories before deletion, then confirm it is absent.

## Required final report

Return one of: **PASS**, **PASS WITH FOLLOW-UP**, or **FAIL**.

Include:

- target repository name and absolute path
- Windows version and architecture
- Codex Desktop package, PATH-resolved Codex CLI (with executable path), Node.js, Git, expected checkout, plugin, npm package, and adapter versions, including whether the plugin release version matched the checkout; report the Desktop-bundled CLI as unavailable when Windows prevents obtaining it
- installation path used: plugin UI or verified-package fallback
- before/after Git status
- files created, updated, preserved, customized, missing, or drifted/broken
- complete wizard check counts and repository/profile state
- whether restart succeeded cleanly
- whether exactly one repo-scoped `$sdlc` appeared and answered correctly, plus any preserved user-owned global `$sdlc`
- every warning or error with diagnostic wording preserved but all sensitive values redacted
- redacted screenshots or visible transcript evidence
- confirmation that no commit, push, tag, publish, deployment, or PR occurred
- whether the repository is ready for normal work with `$sdlc`

For every defect, append a **GitHub-issue-ready** block containing:

- concise title
- severity and user impact
- expected behavior
- actual behavior
- exact reproduction steps
- environment and versions
- relevant logs/output with secrets removed
- workaround, only if one was safely verified without changing wizard internals

Stop after the report. Do not begin the product's implementation work until the installation result is accepted.
