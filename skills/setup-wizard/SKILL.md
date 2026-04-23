---
name: setup-wizard
description: Setup wizard for Codex — scans the repo, builds confidence per data point, asks only what it cannot resolve, and generates repo-specific SDLC docs. Use for first-time setup or re-running setup.
---

# Setup Wizard

## Purpose

You are a confidence-driven setup wizard for Codex. Scan the project, infer as much as possible, and ask only about unresolved preferences or missing facts.

Do not ask a fixed checklist. Do not ask what you already know.

## Reasoning policy

Default to `xhigh` in this repo. Setup is one-time, high-leverage work and should use the highest planning discipline by default.

## Mandatory first action

Before doing anything else, read the repo-local context that already exists.

Read these when present:

- `AGENTS.md`
- `README.md`
- `ROADMAP.md`
- `SDLC-LOOP.md`
- `START-SDLC.md`
- `PROVE-IT.md`
- `TESTING.md`
- `ARCHITECTURE.md`

If you are running inside the `codex-sdlc-wizard` repo itself, also read:

- `README.md`
- `CODEX_ADAPTER_PLAN.md`

Treat those files as the source of truth for what already exists. Do not generate duplicates blindly.

## Execution checklist

### Step 1: Auto-scan the project

Scan the project root for:

- package managers and dependency manifests
- source directories
- test directories
- test frameworks and config files
- lint / format tools
- CI / workflow files
- deployment config
- branding / design system artifacts
- existing SDLC docs
- scripts for lint, test, build, typecheck
- database / cache indicators
- domain indicators:
  - firmware / embedded
  - data science
  - CLI tool
  - web / API as the default fallback

### Step 2: Build a confidence map

For each setup data point, classify it as:

- resolved (detected)
- resolved (inferred)
- unresolved

Use this data point set:

- source directory
- test directory
- test framework
- lint command
- type-check command
- run-all-tests command
- single-test-file command
- production build command
- deployment setup
- database(s)
- cache layer
- test duration expectation
- test types present
- coverage config
- project domain
- response detail preference
- testing approach preference
- mocking philosophy preference
- CI shepherd opt-in

Preferences are always unresolved until the user confirms them.

### Step 3: Present findings and fill gaps

Show all detected values grouped by:

- resolved (detected)
- resolved (inferred)
- unresolved

Use bulk confirmation when most values are already known.

Do not generate files until all relevant data points are resolved by:

- detection
- inference + confirmation
- direct user answer

### Step 4: Generate or update repo-specific docs

Preserve existing docs when they are intentional. Prefer updating or extending them over overwriting them.

Generate or refresh these files when missing or when the user asks:

- `TESTING.md`
- `ARCHITECTURE.md`
- `SDLC.md`

Keep `AGENTS.md` repo-specific. Do not replace a strong existing `AGENTS.md` with generic wizard text.

### Step 5: Testing guidance

Generate `TESTING.md` using the detected project domain.

Default templates:

- web / API: practical test diamond
- firmware / embedded: HIL / SIL / config validation / unit
- data science: model evaluation / pipeline integration / data validation / unit
- CLI tool: CLI integration / behavior / unit

Do not force fake percentage precision if the repo risk sits at external boundaries. For systems heavy on APIs, COM, tenants, hardware, or browser automation, bias toward integration tests.

### Step 6: Codex-native setup recommendations

Recommend Codex-specific follow-ups where appropriate:

- skills to invoke
- MCP servers worth installing
- hooks already present or missing
- config.toml adjustments
- repo-local docs that should be added

On Windows, treat `.codex/hooks.json` that still references Bash hook scripts such as `bash-guard.sh` or `session-start.sh` as broken drift, not as an acceptable customization. Repair it to the PowerShell hook set.

Do not pretend Codex has a native `/sdlc` command if it does not.

### Step 7: Verify

Before calling setup complete, verify:

- generated files exist and are non-empty
- SDLC docs are internally consistent
- hooks/docs/skills do not contradict each other
- any suggested commands actually match the repo
- on Windows, active hook config does not still point at Bash hook scripts

### Step 8: Restart and next steps

If new skills or hooks were installed, tell the user to restart Codex.

Then point them at the next entrypoint:

- `$codex-sdlc` for implementation work
- `$update-wizard` for maintenance
- `$feedback` to contribute back

## Rules

- Never ask what you can detect.
- Never use a fixed question count.
- Always preserve intentional repo customizations.
- Always surface reasoning when something is inferred rather than detected.
- Prefer repo-specific truth over generic wizard defaults.
