# Codex SDLC Wizard

An adapter that brings [SDLC Wizard](https://github.com/BaseInfinity/agentic-ai-sdlc-wizard) enforcement to OpenAI's Codex CLI.

## Quick Start

```bash
# Run adaptive interactive setup in the current repo
npx codex-sdlc-wizard@latest

# Start coding with SDLC enforcement
codex --full-auto
```

`codex --full-auto` is the recommended default once this wizard is installed: you keep the repo guardrails and hook enforcement, but day-to-day editing and runs stay low-friction. Use plain `codex` instead if you want more manual confirmation. If a handoff is interrupted and Codex prints a resume id, continue with `codex resume --full-auto <session-id>` for the same low-friction posture.

Bare `npx codex-sdlc-wizard` is the adaptive interactive path. It bootstraps the repo-local guardrails first, then hands off into a live plain Codex setup session so the unresolved setup questions happen inside Codex instead of inside a shell checklist. At that first-run handoff prompt, press Enter for plain `codex` or type `full-auto` if you explicitly want `codex --full-auto`. `setup --yes` still exists for automation, but it is not the normal human path.

Generic npm entrypoint examples: `npx codex-sdlc-wizard`, `npx codex-sdlc-wizard check`, and `npx codex-sdlc-wizard update`.

`update` repairs repo artifacts using the package version you invoked; it does not self-update the npm package. To consume the newest release and apply its repo-side updates in one command, run `npx codex-sdlc-wizard@latest update`.

Useful follow-ups after install:

```bash
npx codex-sdlc-wizard@0.7.14 check
npx codex-sdlc-wizard@0.7.14 update
```

If you want pinned release examples instead of `@latest`, see [Releases](#releases).

## What This Repo Is

This repo is now a **Codex skill plus adaptive installer-style adapter** for Codex projects.

- It ships a repo-root `SKILL.md` for the normal Codex skill install flow.
- It is **not a Codex plugin** today.
- It still ships `install.sh` / `setup.sh` when you want direct repo mutation from GitHub or npm.

| Need | Use | Why |
|------|-----|-----|
| Install a reusable Codex skill from this repo | `SKILL.md` | The repo root is now a Codex skill package for normal GitHub skill-install flow |
| Add SDLC enforcement to an existing Codex project now | `npx codex-sdlc-wizard` or `setup.sh` | The npm package bootstraps then hands off into live Codex setup; direct scripts still exist for advanced/manual shell paths |
| Install a Codex plugin from this repo | Not supported | There is no `.codex-plugin/plugin.json` package here |

## Self-Adapting SDLC Enforcement

This adapter brings the SDLC Wizard discipline into Codex today with hard guardrails, repo-local guidance, and adaptive setup/update flows that work in existing projects.

**What works today:**
- Hard enforcement hooks that block bad habits (`git commit` without proof, `git push` without review)
- AGENTS.md guidance for planning, confidence tracking, TDD, and review
- Non-destructive installer that merges into your existing Codex config
- Adaptive setup that bootstraps first and then continues inside Codex when you use the default npm entrypoint
- `check` / `update` flows for drift detection and selective repair

**What's still coming from upstream:**
- richer scoring mechanisms and self-improvement from E2E evaluation
- more domain-adaptive guidance refinements beyond the current templates

## Self-Evolving

This adapter tracks the upstream [SDLC Wizard](https://github.com/BaseInfinity/agentic-ai-sdlc-wizard). A weekly sync workflow checks for upstream releases and opens follow-up issues here when translation work is needed.

## What It Does

| SDLC Goal | Enforcement | Level |
|-----------|-------------|-------|
| TDD workflow | AGENTS.md guidance | Soft (Codex has no file-edit hooks) |
| git commit gate | PreToolUse blocks `git commit` | **Hard** |
| git push gate | PreToolUse blocks `git push` | **Hard** |
| SDLC baseline | repo docs + installed skills | **Hard/Soft mix** |
| Session init | SessionStart hook | Warns if AGENTS.md is missing |

## Model Profiles

The wizard supports two wizard-owned model profiles:

- `mixed`: `gpt-5.4-mini` for the main pass plus `gpt-5.5` at `xhigh` for review.
  Tradeoff: better speed, lower latency, and lower token usage on routine work after bootstrap.
- `maximum`: `gpt-5.5` at `xhigh` throughout.
  Tradeoff: higher latency and token usage in exchange for the most stable and thorough "ultimate mode."

How to choose:

```bash
# recommended interactive bootstrap path
npx codex-sdlc-wizard@0.7.14 --model-profile maximum

# interactive bootstrap with the efficiency-first profile if you already know you want it
npx codex-sdlc-wizard@0.7.14 --model-profile mixed

# floating latest release with the same bootstrap recommendation
npx codex-sdlc-wizard@latest --model-profile maximum
```

Interactive setup should ask which profile you want when you do not pass `--model-profile`, and it should recommend `maximum` as the safer bootstrap default.

Low-confidence rule:
- Default to `xhigh` in this repo when the work is meta, setup-heavy, or otherwise high-blast-radius.
- if confidence is below `95%`, research more first
- if it still stays below `95%`, escalate review to `xhigh`
- prefer `maximum` for abstract, complex, or high-blast-radius work

The wizard stores the selected profile in `.codex-sdlc/model-profile.json` so the repo can keep that choice explicit.
It also writes the matching repo-local Codex config to `.codex/config.toml` so trusted Codex sessions use the selected profile instead of silently inheriting stronger user-level defaults.

`mixed` is wizard policy, not a native Codex mode. The wizard maps it to:

```toml
model = "gpt-5.4-mini"
model_reasoning_effort = "xhigh"
review_model = "gpt-5.5"

[features]
codex_hooks = true
```

`maximum` maps to:

```toml
model = "gpt-5.5"
model_reasoning_effort = "xhigh"

[features]
codex_hooks = true
```

Codex only loads project-local `.codex/config.toml` for trusted projects. Once trusted, project config overrides user config in `~/.codex/config.toml`; the wizard does not edit your global config.

Bootstrap recommendation:
- setup/update should use `maximum`; routine work after bootstrap should use `mixed`
- use `maximum` for setup/update because bootstrap work has higher blast radius
- switch back to `mixed` for routine day-to-day work after the repo is stable

Repo-specific maintainer rule:
- consumer repos can choose `mixed` or `maximum`
- this repo always stays on `maximum` (`gpt-5.5` at `xhigh` throughout); do not switch `codex-sdlc-wizard` maintenance to `mixed`, mini-only, or lower-reasoning profiles because it is unusually meta and high-blast-radius

## Repo-Scoped Skills

`install.sh` and `setup.sh` scaffold repo-local Codex skills under `.agents/skills`.

Repo-scoped skill coverage is still a work in progress:

- `$sdlc` is the supported public workflow skill today
- `gdlc` (gaming) and `rdlc` (research) are the next planned repo-scoped skills

Canonical entrypoint: `$sdlc`. `/sdlc` is historical shorthand for the missing slash-command idea, not an invocation command. Adapter-specific SDLC aliases are legacy migration debris and should not appear as second user-facing workflows.

These are Codex-native skill folders, so a fresh Codex session can discover them directly from repo scope. After install or setup, restart Codex so repo-scoped skills are loaded cleanly.

The bridge here is explicit, not magical: this adapter ships the Codex-native skill copies that target repos consume. It does not depend on local `.claude/skills/*` paths being present in the target repo.

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

## Releases

Versioned releases for this adapter live at:

https://github.com/BaseInfinity/codex-sdlc-wizard/releases

If you are consuming this repo in a real project, prefer a tagged release over `main`.

```bash
# npm / npx pinned to the current release
npx codex-sdlc-wizard@0.7.14

# npm / npx floating on the newest published release
npx codex-sdlc-wizard@latest

# Codex skill install
# Install this repository through the normal GitHub skill-install flow
# so $codex-sdlc-wizard is available inside Codex

# git-based install
git clone --branch v0.7.14 --depth 1 https://github.com/BaseInfinity/codex-sdlc-wizard.git /tmp/codex-sdlc-wizard
```

### Maintainer Release Flow

This adapter should follow the same semver-tag plus GitHub Release rhythm as the upstream wizard.
Use [RELEASE.md](RELEASE.md) as the mandatory pre-tag checklist: sync to latest `origin/main`, run the full proof suite, and only then tag.

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

1. Copies `AGENTS.md` (skips if exists, so your customizations are safe)
2. Copies `SDLC-LOOP.md`, `START-SDLC.md`, and `PROVE-IT.md` if missing
3. Creates or merges `.codex/config.toml` with `codex_hooks = true`
4. Installs `.codex/hooks.json` (backs up existing)
5. Copies hook scripts to `.codex/hooks/`
6. Installs repo-scoped skills at `.agents/skills/sdlc/SKILL.md` and `.agents/skills/adlc/SKILL.md`
7. Installs the current global Codex skill set under `~/.codex/skills`

In other words, `install.sh` mutates the target repo by adding or updating `AGENTS.md`, `.codex/config.toml`, `.codex/hooks.json`, `.codex/hooks/*`, and the repo-scoped skills. It also writes `.codex-sdlc/model-profile.json` so the chosen profile is explicit. Existing `.codex/config.toml` files are merged: model keys and `[features].codex_hooks` are patched, while MCP, sandbox, approval, and other custom settings are preserved.

### Requirements

- Codex CLI (`npm i -g @openai/codex`)
- `bash` (3.x+ macOS, 4.x+ Linux, Git Bash on Windows for the shell path)
- Node.js 18+

## E2E Proven

All hooks are verified in real Codex CLI sessions, not just unit tested in isolation.

## Testing

```bash
# Release contract tests (workflow + docs)
bash tests/test-release.sh

# Packaging smoke test (clean temp project, validates install path)
bash tests/test-packaging.sh

# Codex skill package smoke test
bash tests/test-skill.sh

# npm / npx packaging smoke test, including the packed-tarball scratch smoke
bash tests/test-npm.sh

# Unit tests (no API calls, fast)
bash tests/test-adapter.sh
bash tests/test-setup.sh
bash tests/test-update.sh

# E2E tests (opt-in: requires codex CLI + auth, consumes tokens)
CODEX_E2E=1 bash tests/test-e2e.sh
```

- Release contract tests for semver tags, GitHub Releases, and README release docs
- Packaging smoke tests for the documented installer path and README packaging contract
- Skill packaging tests for SKILL.md, agents/openai.yaml, and dual-distribution docs
- npm packaging smoke tests for package metadata, packed contents, and npm exec
- Adapter, setup, and update tests for the Codex-specific behavior surface
- E2E integration tests are token-consuming and opt-in; use `CODEX_E2E=1 bash tests/test-e2e.sh` when you explicitly want real Codex sessions proving hooks fire

## Upstream

Based on [agentic-ai-sdlc-wizard](https://github.com/BaseInfinity/agentic-ai-sdlc-wizard). Same SDLC philosophy, translated to Codex's current tool model with Codex-native skills, repo hooks, and adaptive setup/update flows.

## Community

Come join **[Automation Station](https://discord.com/invite/fGPEF7GHrF)** — a community Discord packed with software engineers bringing 40+ years of combined experience across every area of the stack (frontend, backend, infra, embedded, data, QA, DevOps, you name it). Share patterns, ask questions, compare notes on AI agents, automation, and SDLC tooling.

## License

MIT
