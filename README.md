# Codex SDLC Wizard

An adapter that brings [SDLC Wizard](https://github.com/BaseInfinity/agentic-ai-sdlc-wizard) enforcement to OpenAI's Codex CLI.

## What This Repo Is

This repo is now a **Codex skill plus installer-style adapter** for Codex projects.

- It ships a repo-root `SKILL.md` for the normal Codex skill install flow.
- It is **not a Codex plugin** today.
- It still ships `install.sh` / `setup.sh` when you want direct repo mutation from GitHub or npm.

| Need | Use | Why |
|------|-----|-----|
| Install a reusable Codex skill from this repo | `SKILL.md` | The repo root is now a Codex skill package for normal GitHub skill-install flow |
| Add SDLC enforcement to an existing Codex project now | `install.sh` or `setup.sh` | The skill and npm package both wrap the same installer scripts for target repos |
| Install a Codex plugin from this repo | Not supported | There is no `.codex-plugin/plugin.json` package here |

## Self-Adapting SDLC Enforcement

Like a suit that molds to its wearer, the SDLC Wizard adapts to YOUR project. The Claude Code version reads your repo's language, framework, test runner, and domain to generate tailored docs, hooks, and config. This Codex adapter brings that same philosophy — starting with universal SDLC enforcement hooks, evolving toward full project-adaptive setup.

**What works today:**
- Hard enforcement hooks that block bad habits (git commit without tests, push without review)
- AGENTS.md guidance for TDD, planning, and confidence tracking
- Non-destructive installer that merges into your existing Codex config

**What's coming (inherited from upstream):**
- Project-adaptive setup wizard (reads your repo, generates tailored AGENTS.md)
- Scoring mechanisms and self-improvement from E2E evaluation
- Domain-adaptive testing guidance (firmware, web, data science, etc.)

## Self-Evolving

This adapter evolves automatically with the upstream [SDLC Wizard](https://github.com/BaseInfinity/agentic-ai-sdlc-wizard). A weekly CI workflow detects new upstream releases and opens sync issues. As the Claude Code wizard gains new capabilities (scoring, self-improvement, degradation detection), they get translated to Codex format here.

## What It Does

| SDLC Goal | Enforcement | Level |
|-----------|-------------|-------|
| TDD workflow | AGENTS.md guidance | Soft (Codex has no file-edit tools to hook) |
| git commit gate | PreToolUse blocks `git commit` | **Hard** (stronger than CC wizard!) |
| git push gate | PreToolUse blocks `git push` | **Hard** (stronger than CC wizard!) |
| SDLC baseline | UserPromptSubmit hook | Context injection every prompt |
| Session init | SessionStart hook | Warns if AGENTS.md missing |

## Quick Start

```bash
# Install the current pinned release from npm via npx
npx codex-sdlc-wizard@0.7.0

# Or float on the latest published release
npx codex-sdlc-wizard@latest

# Or clone the adapter release directly
git clone --branch v0.7.0 --depth 1 https://github.com/BaseInfinity/codex-sdlc-wizard.git /tmp/codex-sdlc-wizard
cd your-project
bash /tmp/codex-sdlc-wizard/install.sh

# Start coding with SDLC enforcement
codex --full-auto
```

`codex --full-auto` is the recommended default once this wizard is installed: you keep the repo guardrails and hook enforcement, but day-to-day editing/runs stay low-friction. Use plain `codex` instead if you want more manual confirmation.

If you want actual model-choice numbers instead of anecdotes, record slices in [benchmarks/model-experiment.csv](/Users/stefanayala/codex-sdlc-wizard/benchmarks/model-experiment.csv) and summarize them with:

```bash
bash scripts/summarize-model-experiment.sh
```

The current threshold for recommending `gpt-5.4-mini` as the main pass with `xhigh` review is:
- sample size `>= 20`
- end-to-end success `>= 95%`
- follow-up rate `<= 10%`
- cycle-time improvement vs all-`xhigh` `>= 15%`

If you want to know whether this wizard is ready for default use across real repos, track pilot installs in [benchmarks/pilot-rollout.csv](/Users/stefanayala/codex-sdlc-wizard/benchmarks/pilot-rollout.csv) and summarize them with:

```bash
bash scripts/summarize-pilot-rollout.sh
```

The current default-use gate is:
- 3-5 pilot repos
- pilot success `>= 95%`
- no more than `1` reusable wizard bug across the pilot set

## Model Profiles

The wizard now supports two wizard-owned model profiles:

- `mixed`: `gpt-5.4-mini` for the main pass plus `gpt-5.4` at `xhigh` for review.
  Tradeoff: better speed, lower latency, and lower token usage on routine work after bootstrap.
- `maximum`: `gpt-5.4` at `xhigh` throughout.
  Tradeoff: higher latency and token usage in exchange for the most stable and thorough "ultimate mode." Prefer this for setup/update bootstrap work.

How to choose:

```bash
# recommended bootstrap path
npx codex-sdlc-wizard@0.7.0 setup --yes --model-profile maximum

# routine work can switch back to the efficiency-first profile later
npx codex-sdlc-wizard@0.7.0 setup --yes

# floating latest release with the same bootstrap recommendation
npx codex-sdlc-wizard@latest setup --yes --model-profile maximum
```

Interactive `setup` should ask which profile you want when you do not pass `--yes` or `--model-profile`, and it should recommend `maximum` as the safer bootstrap default.

Low-confidence rule:
- if confidence is below `95%`, research more first
- if it still stays below `95%`, escalate review to `xhigh`
- prefer `maximum` for abstract, complex, or high-blast-radius work

The wizard stores the selected profile in `.codex-sdlc/model-profile.json` so the repo can keep that choice explicit. The profile toggle ships before the experiment is finished, but the long-term default recommendation still stays gated on the 20-slice model experiment.

Bootstrap recommendation:
- setup/update should use `maximum`; routine work after bootstrap should use `mixed`
- use `maximum` for setup/update because bootstrap work has higher blast radius
- switch back to `mixed` for routine day-to-day work after the repo is stable

Repo-specific maintainer rule:
- consumer repos can choose `mixed` or `maximum`
- this repo stays on `maximum`; `codex-sdlc-wizard` itself is unusually meta and high-blast-radius

For adaptive setup instead of the basic installer:

```bash
npx codex-sdlc-wizard@0.7.0 setup --yes
```

If you want Codex to discover this as a reusable skill, install this repository through the normal GitHub skill-install flow. The repo root now contains `SKILL.md` and `agents/openai.yaml`, while the bundled skill behavior still delegates real repo mutation to `install.sh` / `setup.sh`.

## Repo-Scoped Skills

`install.sh` and `setup.sh` now scaffold repo-local Codex skills under `.agents/skills`.

Repo-scoped skill coverage is still a work in progress:

- `$sdlc` is the supported public workflow skill today
- `gdlc` (gaming) and `rdlc` (research) are the next planned repo-scoped skills

These are Codex-native skill folders, so a fresh Codex session can discover them directly from repo scope. After install or setup, restart Codex so repo-scoped skills are loaded cleanly.

The bridge here is explicit, not magical: this adapter ships the Codex-native skill copies that target repos consume. It does not depend on local `.claude/skills/*` paths being present in the target repo. Some additional internal or experimental repo-scoped skill support may still exist under the hood, but `$sdlc` is the main public contract today.

## Honest Codex SDLC Shape

The current recommended Codex-native architecture is explicit:

- `skills = explicit workflow layer`
- `hooks = silent event enforcement`
- `repo docs = source of local truth`

That means:
- use repo-scoped or installed skills for the user-facing workflow contract
- use hooks to block or warn silently at the right events
- keep `AGENTS.md`, `ARCHITECTURE.md`, `TESTING.md`, and related repo docs as the local source of truth

What not to do:
- do not pretend Codex has native slash commands when it does not
- do not overload hooks to act as the user-facing workflow layer

## Feedback Flow and Repo Focus

When you dogfood this wizard in a product repo, keep the active session focused on that product repo.

- if you discover a **proven reusable** wizard lesson, prefer filing a **direct GitHub issue** in `codex-sdlc-wizard` right away
- if you are reporting a consumer-facing failure, use the repo's **Consumer bug report** template so command, repo shape, failed step, and auth context are captured consistently
- keep building the **product repo** in the current session
- only switch into live wizard work when the product repo is **actually blocked**

This keeps dogfooding useful without turning every implementation session into wizard meta-work.

## Auth-Heavy Workflow Boundaries

Some repos still hit auth-heavy steps that the agent cannot finish fully on your behalf, especially on Windows when Microsoft Graph auth lands in WAM / MFA / browser sign-in flows.

What stays agent-owned:
- command shape and wrapper scripts
- prerequisite checks and environment validation
- outcome classification and next-step guidance
- verify/resume commands after the live sign-in completes

What stays user-owned:
- your live Windows / browser sign-in interaction
- WAM / MFA approval prompts that land in your session

How repos should wrap these flows:
1. give Codex an explicit auth-start command
2. let the user complete the live sign-in step
3. give Codex an explicit verify/resume command so the workflow continues cleanly afterward

This should be presented as a boundary, not a refusal. The agent is not refusing the work; it still owns setup, checks, classification, and the resume path, while your live sign-in remains user-owned.

## Capability Detectors for Auth / License-Sensitive Repos

If account type, tenant shape, licensing, or permission state determines what is possible in a repo, do not leave users hand-running vague provider commands.

Prefer a repo-local helper such as:
- `doctor`
- `check-capability`
- `Test-*Access.ps1`

Bias setup and troubleshooting toward one-command classification first. The goal is to turn provider vagueness into explicit repo-owned signals like `OK`, `NotConnected`, `PermissionError`, or `UnsupportedAccount`.

Treat account type, license, tenant, and permission state as setup data, not just troubleshooting noise. Codex should be able to run the detector, classify the current lane, and continue from a clear starting point.

## Releases

Versioned releases for this adapter live at:

https://github.com/BaseInfinity/codex-sdlc-wizard/releases

If you are consuming this repo in a real project, prefer a tagged release over `main`.

```bash
# npm / npx pinned to the current release
npx codex-sdlc-wizard@0.7.0

# npm / npx floating on the newest published release
npx codex-sdlc-wizard@latest

# Codex skill install
# Install this repository through the normal GitHub skill-install flow
# so $codex-sdlc-wizard is available inside Codex

# git-based install
git clone --branch v0.7.0 --depth 1 https://github.com/BaseInfinity/codex-sdlc-wizard.git /tmp/codex-sdlc-wizard
```

### Maintainer Release Flow

This adapter should follow the same semver-tag plus GitHub Release rhythm as the upstream wizard.

```bash
# After tests pass on main
git tag vX.Y.Z
git push origin vX.Y.Z
```

Pushing a `vX.Y.Z` tag triggers this repo's release workflow, publishes the npm package, and publishes GitHub Release notes automatically. `workflow_dispatch` exists as a retry path for an existing tag if a release job needs to be rerun.

To enable npm publish from GitHub Actions, configure npm trusted publishing for this package instead of storing a long-lived token:

1. Open the npm package settings for `codex-sdlc-wizard`
2. Go to `Trusted publishing`
3. Choose `GitHub Actions`
4. Configure:
   `Organization or user`: `BaseInfinity`
   `Repository`: `codex-sdlc-wizard`
   `Workflow filename`: `release.yml`
   `Environment name`: leave blank unless you later add a protected GitHub environment

The workflow uses GitHub OIDC trusted publishing, validates that the tag matches `package.json`, and skips `npm publish` on reruns when that exact version already exists on npm. No `NPM_TOKEN` GitHub secret is required.

### What `install.sh` Changes

1. Copies `AGENTS.md` (skips if exists — your customizations are safe)
2. Creates/merges `.codex/config.toml` with `codex_hooks = true`
3. Installs `.codex/hooks.json` (backs up existing)
4. Copies hook scripts to `.codex/hooks/`

In other words, `install.sh` mutates the target repo by adding or updating `AGENTS.md`, `.codex/config.toml`, `.codex/hooks.json`, and `.codex/hooks/*.sh`.
It also scaffolds repo-scope Codex skills at `.agents/skills/sdlc/SKILL.md` and `.agents/skills/adlc/SKILL.md`.

### Requirements

- Codex CLI (`npm i -g @openai/codex`)
- `bash` (3.x+ macOS, 4.x+ Linux)
- `jq` (for hook JSON parsing)

## E2E Proven

All hooks are verified in real Codex CLI sessions — not just unit tested in isolation:

```
PASS: E2E: Codex session completed with hooks loaded
PASS: E2E: git commit was blocked — HEAD is still 'init'
PASS: E2E: git push was blocked by hook
PASS: E2E: Normal commands execute with hooks active
PASS: E2E: Session works without AGENTS.md (hook warns, doesn't crash)
```

## Testing

```bash
# Release contract tests (workflow + docs)
bash tests/test-release.sh

# Packaging smoke test (clean temp project, validates install path)
bash tests/test-packaging.sh

# Codex skill package smoke test
bash tests/test-skill.sh

# npm / npx packaging smoke test
bash tests/test-npm.sh

# Unit tests (no API calls, fast)
bash tests/test-adapter.sh

# E2E tests (requires codex CLI + auth, costs tokens)
bash tests/test-e2e.sh
```

- Release contract tests for semver tags, GitHub Releases, and README release docs
- Packaging smoke tests for the documented installer path and README packaging contract
- Skill packaging tests for SKILL.md, agents/openai.yaml, and dual-distribution docs
- npm packaging smoke tests for package metadata, packed contents, and npm exec
- 15 behavioral unit tests (hook behavior, payload format, config merge, install)
- 5 E2E integration tests (real Codex sessions proving hooks fire)

## Upstream

Based on [agentic-ai-sdlc-wizard](https://github.com/BaseInfinity/agentic-ai-sdlc-wizard) v1.31.0. Same SDLC philosophy, translated to Codex's Bash-only tool model (~70% parity).

## Community

Come join **[Automation Station](https://discord.com/invite/fGPEF7GHrF)** — a community Discord packed with software engineers bringing 40+ years of combined experience across every area of the stack (frontend, backend, infra, embedded, data, QA, DevOps, you name it). Share patterns, ask questions, compare notes on AI agents, automation, and SDLC tooling.

## License

MIT
