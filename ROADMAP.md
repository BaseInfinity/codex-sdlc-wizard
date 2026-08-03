# Codex SDLC Wizard Roadmap

## Current State

- `codex-sdlc-wizard@0.7.34` and `v0.7.34` are the current published release; `0.7.35` is the Desktop-readiness release candidate
- npm trusted publishing is configured and the GitHub release workflow is now proven for real OIDC publish
- the repo now ships a skills-only Codex plugin (`.codex-plugin/plugin.json` pointing to `skills/`), one installer skill at `skills/codex-sdlc-wizard/SKILL.md`, and the installer/setup adapter (`install.sh`, `setup.sh`)
- the plugin declares no MCP servers, apps, or plugin-level hooks; repo-scoped enforcement remains the responsibility of the adaptive installer
- the npm CLI now defaults to adaptive interactive setup instead of requiring an explicit `setup` subcommand for the main human path
- setup now layers deterministic scan plus live Codex `gpt-5.6-sol` / `high` refinement when available
- setup now keeps detected values automatically, asks inferred values conversationally, and asks only missing core repo facts directly
- the repo-scoped Codex discovery bridge for `$sdlc` is now part of the shipping path
- consumer-path hardening for auth-heavy boundaries, capability detectors, and docs-strong scaffold repos is shipped
- honest Codex architecture guidance, confidence/reporting guidance, direct-issue capture, and repo-focus rules are now part of the shipped path
- the model-profile toggle is now shipped as a user choice:
  - `mixed`: `gpt-5.6-terra` `medium` main pass + `gpt-5.6-sol` review with an explicit `high` effort override
  - `maximum`: `gpt-5.6-sol` / `high` throughout
- researched GPT-5.6 reasoning policy now uses `high` as the consumer agentic-coding default, adapts `xhigh` escalation scopes to detected repo risks, preserves this repo's measured Sol `xhigh` maintainer exception, and keeps Max/Ultra as explicit escalations instead of defaults
- setup/install now offer issue-ready feedback for obvious wizard-level failures instead of only failing vaguely
- install/setup/update now use `maximum` as the standing Sol `high` default; `mixed` is an experimental explicit opt-in that update preserves only when already selected
- setup/update guidance now treats verification as diagnostic for product failures and stops before editing application code or application tests without explicit user consent
- setup/update guidance now tells users to exit and reopen Codex after hook/skill repairs, without rerunning setup/update just for that restart
- install/setup/update now write and repair repo-local `.codex/config.toml` model keys for the selected profile, while preserving unrelated MCP, sandbox, approval, and custom config
- first-run live setup now defaults to plain `codex` after bootstrap and requires an explicit `full-trust` choice to start that setup handoff with `codex --dangerously-bypass-approvals-and-sandbox`
- first-run handoff now uses a clearer prompt, recommends model-explicit `codex resume -m ... -c ...` for interrupted handoffs, and avoids the deprecated Windows `shell:true` plus args launcher path
- first-run live Codex handoff now runs as a managed child process with opt-in timeout cleanup, POSIX signal forwarding, process-group termination, repeated-interrupt handling, and explicit retry/resume guidance
- setup/install output now prints Codex's canonical full-trust flag (`--dangerously-bypass-approvals-and-sandbox`) for users who normally say yolo-style sessions, while keeping full-trust distinct from historical full-auto wording
- update guidance now frontloads the npm version boundary: `$update-wizard` repairs repo artifacts, while `npx codex-sdlc-wizard@latest update` consumes the newest package
- setup guidance now includes Codex Desktop handoff notes for auth-heavy browser/computer-use setup flows
- generated setup docs and shipped skills now include a task-routing gate that identifies CLI, Desktop/computer-use, browser automation, or human-only lanes before giving execution steps
- generated setup docs now include a demo runtime claim gate so demo-ready claims must prove the real human-facing runtime, action runner, proof status, live artifact, mutation gates, and not-claimed boundary
- setup guidance now includes Microsoft 365 auth-lane proof rules for tenant-bound Graph PowerShell and fallback OAuth evidence
- sponsor metadata is now shipped for GitHub Sponsors and npm funding surfaces
- the package now treats `$sdlc` as the single canonical public workflow entrypoint, keeps the Codex display name lowercase, and blocks legacy `$codex-sdlc` or imperative `/sdlc` wording from returning
- setup/install now keep `$sdlc` repo-scoped, install no extra repo-scoped lifecycle skills by default, and install only global helper skills, avoiding same-name global/repo skill collisions
- repo-root skill installs now keep bundled helper definitions under non-discoverable `SKILL.template.md` names and materialize `SKILL.md` only in intended destinations, preventing recursive duplicate skill discovery
- setup now detects Playwright MCP browser tooling/profile policy and documents explicit opt-in isolation versus shared persistent auth-heavy flows without rewriting `.mcp.json`
- setup/update now repair stale platform-specific hook wiring and install universal Node hook entrypoints so a checked-in `.codex/hooks.json` does not flip between macOS Bash and Windows PowerShell commands
- setup/update now write `[features].hooks = true`, migrate deprecated `[features].codex_hooks` config, and remind users to review pending repo hooks through `/hooks`
- generated Node hooks now use `.cjs` entrypoints so consumer repos with `"type": "module"` do not break on CommonJS `require`
- Codex CLI `0.144.0+` is required for GPT-5.6 profiles; its hook surface is recognized, and the wizard intentionally installs `SessionStart`, `PreToolUse`, `PreCompact`, and `PostCompact` while leaving `PermissionRequest`, `PostToolUse`, `UserPromptSubmit`, and `Stop` unwired until a proven SDLC need exists
- compact lifecycle hooks now preserve SDLC carry-forward context around Codex compaction without blocking normal compaction
- update now repairs legacy `.js` hook commands and stale `.js` hook manifest entries, including old matching files
- the git guard is now proof-aware: fresh reviewed SDLC proof allows commit/push, while missing, stale, cross-repo, or mismatched-workdir proof still blocks
- public install/README/skill copy now keeps unreleased future workflow labels out of handoff text
- the repo now ships a consumer bug-report template for install/setup/runtime failures
- the public README now leads with the real `@latest` adaptive setup path and keeps the top section consumer-focused
- the public README now has consumer-parity sections that explain why to use the wizard without exposing later ecosystem branding
- the official Codex plugin distribution boundary is documented in README and ROADMAP: ChatGPT Work, the Codex desktop app, and Codex CLI share plugin distribution, while ordinary Chat does not support plugins
- maintainers can run `node scripts/run-proof-suite.cjs` for bounded parallel release proof without dropping any checks, with `--serial` available for debugging
- benchmark and pilot-rollout ledgers now exist so model/default-use decisions can be measured, not guessed
- release, packaging, npm, skill, setup, adapter, update, and E2E tests are green when the parity merge is complete
- bare `npx codex-sdlc-wizard@latest` now auto-runs the update/check-repair path in already-initialized clones, so cross-machine checkouts sync without remembering separate `check`/`update` commands
- setup now supports optional `--goals` generation for a manifest-tracked `GOALS.md` active-scope contract, while `ROADMAP.md` remains backlog/history
- README and generated `GOALS.md` now document manual Codex `/goal` usage as SDLC-backed active work anchored to `$sdlc`, confidence/verification gates, and clean-break commits; programmatic `/goal` automation remains unassumed
- setup/check now reject unknown arguments before mutating or inspecting the current directory, so mistyped flags do not silently operate on the wrong repo
- upstream sync has been reviewed through `agentic-ai-sdlc-wizard` / `claude-sdlc-wizard` `v1.73.0`; Codex-relevant workflow hardening was ported, while Claude-only precompact hooks and research churn remain intentionally out of scope unless they prove reusable here

## Next Release Cycle

### 0.7.35

Purpose: harden plugin-driven installation before final supported-surface validation and public directory submission.

Scope:
- preserve unrelated host hooks while replacing only wizard-owned hook entries during install and repair
- keep successful artifact installation successful when the optional nested Codex handoff cannot start or exits with an ordinary failure
- refresh manifest hashes only for installer-touched artifacts and preserve untouched customizations
- distinguish plugin exploration, install/repair, and repo-local lifecycle intents in the picker
- validate the exact release candidate through Claude-driven black-box Codex Desktop and ChatGPT Work E2E before publishing

## Tracker Cleanup

The `0.7.35` stabilization set is intentionally limited to #55, #56, and the picker-intent fix from #69/PR #70. Issue #66 owns the final supported-surface E2E and public directory submission; remaining docs/research issues stay outside this release lane.

- open a new issue only when pilot consumption exposes another proven reusable wizard bug
- avoid speculative backlog churn while `0.7.35` is being validated on supported Codex surfaces

## Remaining Backlog

After `0.7.35`, the main backlog is:

- complete supported-surface plugin validation and submit the public directory listing
- any new reusable wizard fixes discovered during the pilot set
- model-profile measurement data collection for `mixed` vs `maximum`
- optional Skill Creator maintenance research after the active backlog stays under control

## Official Codex Plugin Distribution Plan

Official Codex docs make plugins the installable distribution unit for reusable skills, apps, MCP servers, and presentation assets. The implementation outcome for this repo is a skills-only plugin: `.codex-plugin/plugin.json` points to the conventional `skills/` directory and its single installer skill, while npx remains the repo-mutation engine.

- Package the manifest in `codex-sdlc-wizard@0.7.35` so the same artifact carries the plugin skill and the existing CLI/installer.
- Validate discovery in ChatGPT Work, the Codex desktop app, and Codex CLI. Ordinary Chat remains outside the supported plugin surfaces.
- Keep MCP servers, apps, and plugin-level hooks out until a proven product need exists; the installer continues to write repo-local hooks and config.
- The official submission portal is live; the public listing is pending supported-surface validation and submission.
- Do not imply official OpenAI endorsement unless the plugin is actually accepted into the official Plugin Directory.

## Working Order

1. Validate the skills-only plugin in ChatGPT Work, the Codex desktop app, and Codex CLI
2. Publish the version-aligned npm package and verify clean installation
3. Submit the public listing through the live submission portal after supported-surface validation
4. Keep pilot rollout and stabilization patches tied to real consumption bugs

## Default-Use Gate

Before calling this the default Codex SDLC path, prove it on real pilot repos instead of just repo-self-tests.

- run released builds on 3-5 pilot repos before broadening the default-use claim
- require pilot success >= 95% before default use
- allow no more than 1 reusable wizard bug across the pilot set
- track the pilot set in `benchmarks/pilot-rollout.csv`
- summarize the gate with `bash scripts/summarize-pilot-rollout.sh`

## Later Research

The creator-tool investigation is complete for the distribution decision: `Plugin Creator` established the minimum valid package shape and led to the implemented skills-only plugin. `Skill Creator` remains a possible later maintenance aid rather than a release blocker.

- investigate programmatic `/goal` automation only if Codex exposes a stable CLI/API path; keep manual `/goal` guidance anchored to `$sdlc`
- evaluate `Skill Creator` later as a possible aid for skill-structure maintenance
- keep the implemented `Plugin Creator` manifest contract covered by packaging tests
- run an experimental explicit opt-in measurement of `gpt-5.6-terra` `medium` for the main working pass with a `gpt-5.6-sol` review explicitly overridden to `high`, and compare that against the Sol `high` `maximum` profile
- keep an easy toggle between the two explicit profiles:
  - `mixed`: `gpt-5.6-terra` `medium` main pass plus `gpt-5.6-sol` review with an explicit `high` effort override
  - `maximum`: `gpt-5.6-sol` / `high` for the whole slice
- require a sample of 20 slices before considering whether `mixed` should stop being experimental and become a normal-work recommendation
- numeric target for recommending the mixed mode: at least 95% end-to-end success, follow-up rate <= 10%, and at least a 15% improvement in cycle time versus `maximum`
- separately measure Sol `high` vs Sol `xhigh` before lowering this repo's maintainer exception; preserve this repo's current `xhigh` baseline until Sol `high` meets the same sample, success, follow-up, and improvement gate
- keep Max as a single-task reasoning escalation and Ultra as a subagent-backed parallel-work escalation; most tasks do not need Max or Ultra, and neither becomes a default wizard profile without separate evidence
- escalate abstract, complex, security-sensitive, or high-blast-radius slices to `xhigh` when `high` leaves unresolved risk; do not make every consumer task pay that cost
- keep this behind the active workload so it does not compete with the active pilot-rollout and stabilization backlog
