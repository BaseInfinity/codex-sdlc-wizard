---
name: update-wizard
description: Smart update workflow for Codex SDLC repos — compare current state against wizard expectations, preserve customizations, and update selectively.
---

# Update Wizard

## Purpose

You are a guided update assistant. Your job is to show what changed, detect drift, and help the user adopt updates without flattening their customizations.

Do not blindly overwrite files.

Version boundary: `$update-wizard` updates repo artifacts using the wizard version already installed in the active Codex skill/session. It does not self-update the npm package. To consume the newest published package first, tell the user to run `npx codex-sdlc-wizard@latest update` from the repo, then restart or resume Codex so refreshed skills/hooks/config load.

## Reasoning policy

Default to `xhigh` in this repo. Update work is maintenance architecture, and customized drift makes lower-effort passes too risky by default.

## Scope guard

Update owns the wizard surface: repo metadata, Codex integration artifacts, hooks, skills, helper scripts, and SDLC docs.

During update, do not edit application code, product logic, or application tests. Verification is diagnostic by default: if tests or validation fail outside setup-managed files, summarize the failures and stop. Ask the user before switching from update into implementation work, or hand the remediation to `$sdlc`.

Only auto-fix failures that are directly caused by wizard drift, such as broken hook paths, missing installed skills, contradictory generated docs, stale helper scripts, or Windows hook config that still points at Bash scripts.

Canonical SDLC entrypoint: `$sdlc`. `/sdlc` is historical shorthand for the missing slash-command idea, not an invocation command. Do not create adapter-specific SDLC aliases as second user-facing workflows.

## Mandatory first action

Read the local repo context first:

- `AGENTS.md`
- `README.md`
- `ROADMAP.md`
- `SDLC-LOOP.md`
- `START-SDLC.md`
- `PROVE-IT.md`
- `TESTING.md`
- `SDLC.md`

If running inside `codex-sdlc-wizard`, also read:

- `README.md`
- `CODEX_ADAPTER_PLAN.md`

## Execution checklist

### Step 1: Read installed state

Identify what exists now:

- repo-local SDLC docs
- active hooks and hook config
- installed Codex skills
- customizations that differ from wizard defaults

### Step 2: Compare against expected surface

Expected Codex SDLC surface includes:

- `sdlc`
- `setup-wizard`
- `update-wizard`
- `feedback`
- repo-local SDLC docs as appropriate
- repo-local `.codex/config.toml` model settings that match the selected wizard profile
- hook config and scripts

Group findings as:

- match
- missing
- customized
- drift / broken

On Windows, `.codex/hooks.json` that still points at Bash hook scripts is `drift / broken`, not a customization to preserve.

If `.codex-sdlc/model-profile.json` or `SDLC.md` says one model profile but `.codex/config.toml` still inherits a different user/global model, classify that as drift. Preserve unrelated config keys and only patch the wizard-owned top-level `model`, `model_reasoning_effort`, `review_model`, and `[features].codex_hooks` settings. Explain that `mixed` is wizard policy, not a native Codex mode, and that project config only loads after the repo is trusted.

### Step 3: Show update plan first

Before applying anything, tell the user:

- what is current
- what is missing
- what changed upstream or in the local wizard
- which files are customized and should be preserved

Use human-readable summaries, not giant raw diffs by default.

### Step 4: Apply updates selectively

Missing files can be installed or created.

Customized files should be merged or skipped intentionally.

Never replace strong repo-local docs just to make them look more like the wizard.

### Step 5: Verify

After updates, verify:

- skills exist where expected
- hooks still match the intended quiet enforcement set
- repo-local docs are internally consistent
- customized files were preserved when requested
- on Windows, active hook config does not still reference Bash hook scripts

This verification is diagnostic for product behavior. If a failing command points at application code or application tests unrelated to wizard-managed changes, do not edit application code to force update green. Report the failure, identify why it appears outside update scope, and ask whether to continue under `$sdlc`.

### Step 6: Restart and next steps

If skills, hooks, hook config, or helper scripts were installed or repaired, tell the user to exit and reopen Codex in this repo so the active session reloads them. Tell them: you do not need to rerun update just for that restart. If they closed an interrupted handoff and Codex printed a resume id, recommend `codex resume --full-auto <session-id>` for low-friction continuation, or plain `codex resume <session-id>` when they want manual confirmations.

## Rules

- Never overwrite customizations blindly.
- Prefer merge or extension over replacement.
- Explain drift clearly.
- If the repo is effectively uninitialized, recommend running `$setup-wizard` instead.
- During update, never cross into product remediation without explicit user consent.
