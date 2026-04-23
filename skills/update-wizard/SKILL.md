---
name: update-wizard
description: Smart update workflow for Codex SDLC repos — compare current state against wizard expectations, preserve customizations, and update selectively.
---

# Update Wizard

## Purpose

You are a guided update assistant. Your job is to show what changed, detect drift, and help the user adopt updates without flattening their customizations.

Do not blindly overwrite files.

## Reasoning policy

Default to `xhigh` in this repo. Update work is maintenance architecture, and customized drift makes lower-effort passes too risky by default.

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

- `codex-sdlc`
- `setup-wizard`
- `update-wizard`
- `feedback`
- repo-local SDLC docs as appropriate
- hook config and scripts

Group findings as:

- match
- missing
- customized
- drift / broken

On Windows, `.codex/hooks.json` that still points at Bash hook scripts is `drift / broken`, not a customization to preserve.

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

## Rules

- Never overwrite customizations blindly.
- Prefer merge or extension over replacement.
- Explain drift clearly.
- If the repo is effectively uninitialized, recommend running `$setup-wizard` instead.
