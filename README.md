# Codex SDLC Wizard

An adapter that brings [SDLC Wizard](https://github.com/BaseInfinity/agentic-ai-sdlc-wizard) enforcement to OpenAI's Codex CLI.

## What This Repo Is

This repo is currently an **installer-style adapter** for Codex projects.

- It is **not a Codex skill** today.
- It is **not a Codex plugin** today.
- The supported install path is to run `install.sh` inside the target project you want to enforce.

| Need | Use | Why |
|------|-----|-----|
| Add SDLC enforcement to an existing Codex project now | `install.sh` | This repo ships hooks, config, and baseline docs for a target repo |
| Install a reusable Codex skill from this repo | Not supported yet | Skill packaging is tracked separately and does not exist in the current repo layout |
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
# Install from npm via npx
npx codex-sdlc-wizard@X.Y.Z

# Or clone the adapter release directly
git clone --branch vX.Y.Z --depth 1 https://github.com/BaseInfinity/codex-sdlc-wizard.git /tmp/codex-sdlc-wizard
cd your-project
bash /tmp/codex-sdlc-wizard/install.sh

# Start coding with SDLC enforcement
codex
```

For adaptive setup instead of the basic installer:

```bash
npx codex-sdlc-wizard@X.Y.Z setup --yes
```

## Releases

Versioned releases for this adapter live at:

https://github.com/BaseInfinity/codex-sdlc-wizard/releases

If you are consuming this repo in a real project, prefer a tagged release over `main`.

```bash
# npm / npx
npx codex-sdlc-wizard@X.Y.Z

# git-based install
git clone --branch vX.Y.Z --depth 1 https://github.com/BaseInfinity/codex-sdlc-wizard.git /tmp/codex-sdlc-wizard
```

### Maintainer Release Flow

This adapter should follow the same semver-tag plus GitHub Release rhythm as the upstream wizard.

```bash
# After tests pass on main
git tag vX.Y.Z
git push origin vX.Y.Z
```

Pushing a `vX.Y.Z` tag triggers this repo's release workflow and publishes GitHub Release notes automatically. `workflow_dispatch` exists as a retry path for an existing tag if a release job needs to be rerun.

### What `install.sh` Changes

1. Copies `AGENTS.md` (skips if exists — your customizations are safe)
2. Creates/merges `.codex/config.toml` with `codex_hooks = true`
3. Installs `.codex/hooks.json` (backs up existing)
4. Copies hook scripts to `.codex/hooks/`

In other words, `install.sh` mutates the target repo by adding or updating `AGENTS.md`, `.codex/config.toml`, `.codex/hooks.json`, and `.codex/hooks/*.sh`.

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

# npm / npx packaging smoke test
bash tests/test-npm.sh

# Unit tests (no API calls, fast)
bash tests/test-adapter.sh

# E2E tests (requires codex CLI + auth, costs tokens)
bash tests/test-e2e.sh
```

- Release contract tests for semver tags, GitHub Releases, and README release docs
- Packaging smoke tests for the documented installer path and README packaging contract
- npm packaging smoke tests for package metadata, packed contents, and npm exec
- 15 behavioral unit tests (hook behavior, payload format, config merge, install)
- 5 E2E integration tests (real Codex sessions proving hooks fire)

## Upstream

Based on [agentic-ai-sdlc-wizard](https://github.com/BaseInfinity/agentic-ai-sdlc-wizard) v1.31.0. Same SDLC philosophy, translated to Codex's Bash-only tool model (~70% parity).

## Community

Come join **[Automation Station](https://discord.com/invite/fGPEF7GHrF)** — a community Discord packed with software engineers bringing 40+ years of combined experience across every area of the stack (frontend, backend, infra, embedded, data, QA, DevOps, you name it). Share patterns, ask questions, compare notes on AI agents, automation, and SDLC tooling.

## License

MIT
