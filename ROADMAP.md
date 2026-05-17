# Codex SDLC Wizard Roadmap

## Current State

- `codex-sdlc-wizard@0.7.30` and `v0.7.30` are the current release target for the SDLC-only default repo skill surface
- npm trusted publishing is configured and the GitHub release workflow is now proven for real OIDC publish
- the repo now ships both a Codex skill package (`SKILL.md`, `agents/openai.yaml`) and the installer/setup adapter (`install.sh`, `setup.sh`)
- the npm CLI now defaults to adaptive interactive setup instead of requiring an explicit `setup` subcommand for the main human path
- setup now layers deterministic scan plus live Codex `gpt-5.5` / `xhigh` refinement when available
- setup now keeps detected values automatically, asks inferred values conversationally, and asks only missing core repo facts directly
- the repo-scoped Codex discovery bridge for `$sdlc` is now part of the shipping path
- consumer-path hardening for auth-heavy boundaries, capability detectors, and docs-strong scaffold repos is shipped
- honest Codex architecture guidance, confidence/reporting guidance, direct-issue capture, and repo-focus rules are now part of the shipped path
- the model-profile toggle is now shipped as a user choice:
  - `mixed`: `gpt-5.4-mini` main pass + `gpt-5.5` `xhigh` review
  - `maximum`: `gpt-5.5` / `xhigh` throughout
- setup/install now offer issue-ready feedback for obvious wizard-level failures instead of only failing vaguely
- setup/update guidance now biases bootstrap work toward `maximum` while routine work can switch back to `mixed`
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
- setup now detects Playwright MCP browser tooling/profile policy and documents explicit opt-in isolation versus shared persistent auth-heavy flows without rewriting `.mcp.json`
- setup/update now repair stale platform-specific hook wiring and install universal Node hook entrypoints so a checked-in `.codex/hooks.json` does not flip between macOS Bash and Windows PowerShell commands
- setup/update now write `[features].hooks = true`, migrate deprecated `[features].codex_hooks` config, and remind users to review pending repo hooks through `/hooks`
- generated Node hooks now use `.cjs` entrypoints so consumer repos with `"type": "module"` do not break on CommonJS `require`
- Codex CLI `0.130.0` hook surface is recognized: the wizard intentionally installs `SessionStart`, `PreToolUse`, `PreCompact`, and `PostCompact`, while leaving `PermissionRequest`, `PostToolUse`, `UserPromptSubmit`, and `Stop` unwired until a proven SDLC need exists
- compact lifecycle hooks now preserve SDLC carry-forward context around Codex compaction without blocking normal compaction
- update now repairs legacy `.js` hook commands and stale `.js` hook manifest entries, including old matching files
- the git guard is now proof-aware: fresh reviewed SDLC proof allows commit/push, while missing, stale, cross-repo, or mismatched-workdir proof still blocks
- public install/README/skill copy now keeps unreleased future workflow labels out of handoff text
- the repo now ships a consumer bug-report template for install/setup/runtime failures
- the public README now leads with the real `@latest` adaptive setup path and keeps the top section consumer-focused
- the public README now has consumer-parity sections that explain why to use the wizard without exposing later ecosystem branding
- official Codex skills/plugins docs now have a documented distribution boundary in README and ROADMAP: npm/skill remains current, plugin packaging is future work
- maintainers can run `node scripts/run-proof-suite.cjs` for bounded parallel release proof without dropping any checks, with `--serial` available for debugging
- benchmark and pilot-rollout ledgers now exist so model/default-use decisions can be measured, not guessed
- release, packaging, npm, skill, setup, adapter, update, and E2E tests are green when the parity merge is complete
- bare `npx codex-sdlc-wizard@latest` now auto-runs the update/check-repair path in already-initialized clones, so cross-machine checkouts sync without remembering separate `check`/`update` commands
- setup now supports optional `--goals` generation for a manifest-tracked `GOALS.md` active-scope contract, while `ROADMAP.md` remains backlog/history
- README and generated `GOALS.md` now document manual Codex `/goal` usage as SDLC-backed active work anchored to `$sdlc`, confidence/verification gates, and clean-break commits; programmatic `/goal` automation remains unassumed
- setup/check now reject unknown arguments before mutating or inspecting the current directory, so mistyped flags do not silently operate on the wrong repo
- upstream sync has been reviewed through `agentic-ai-sdlc-wizard` / `claude-sdlc-wizard` `v1.73.0`; Codex-relevant workflow hardening was ported, while Claude-only precompact hooks, plugin packaging, and research churn remain intentionally out of scope unless they prove reusable here

## Next Release Cycle

### 0.7.31

Purpose: continue pilot rollout after the `0.7.30` unknown-argument fail-fast release while keeping new patches tied to proven reusable wizard bugs or verified Codex-native workflow behavior.

Scope:
- keep `0.7.30` as the initialized-clone default-update, current-Codex handoff/full-trust guidance, demo-runtime claim gate, parallel proof-runner, current Codex hooks feature-flag baseline, optional `GOALS.md` active-scope contract, manual `/goal` guidance baseline, and fail-fast unknown-argument baseline for pilot consumption
- keep programmatic `/goal` automation unassumed unless Codex exposes a stable CLI/API path for it
- address the README/discovery/sponsor backlog only in small, separately verified slices
- cut another stabilization patch only if real consumption surfaces another reusable wizard bug
- keep separate model-profile measurement running, but do not let it block pilot rollout work

## Tracker Cleanup

The stabilization tracker is currently clear after the `0.7.30` unknown-argument fail-fast release. Remaining open docs/research issues stay outside the stabilization lane.

- open a new issue only when pilot consumption exposes another proven reusable wizard bug
- avoid speculative backlog churn while `0.7.30` is being consumed on real repos

## Remaining Backlog

After `0.7.30`, the main backlog is:

- README/discovery cleanup for the open docs issues
- any new reusable wizard fixes discovered during the pilot set
- official Codex plugin distribution packaging, after the current npm/skill path stays stable
- model-profile measurement data collection for `mixed` vs `maximum`
- later creator-tool research after the active backlog stays under control

## Official Codex Plugin Distribution Plan

Official Codex docs now make plugins the installable distribution unit for reusable skills, apps, MCP servers, and presentation assets. The current repo remains npm/skill-first until plugin packaging is justified by consumption.

- Keep the current consumer path as `npx codex-sdlc-wizard@latest` plus the existing Codex skill package.
- When packaging as a plugin, add `.codex-plugin/plugin.json`, bundle the public `$sdlc` workflow under plugin `skills/`, keep helper skills scoped as support tooling, and include only required `.mcp.json` or `.app.json` integrations.
- Test local/team discovery through `.agents/plugins/marketplace.json` before considering a public listing.
- Official docs say self-serve plugin publishing is coming soon; treat public listing as blocked until that path is actually available in practice.
- Do not imply official OpenAI endorsement unless the plugin is actually accepted into the official Plugin Directory.

## Working Order

1. Keep pilot rollout and stabilization patches tied to real consumption bugs
2. Work the README/discovery backlog in small verified slices
3. Keep creator-tool investigation behind the active backlog

## Default-Use Gate

Before calling this the default Codex SDLC path, prove it on real pilot repos instead of just repo-self-tests.

- run released builds on 3-5 pilot repos before broadening the default-use claim
- require pilot success >= 95% before default use
- allow no more than 1 reusable wizard bug across the pilot set
- track the pilot set in `benchmarks/pilot-rollout.csv`
- summarize the gate with `bash scripts/summarize-pilot-rollout.sh`

## Later Research

After the current backlog is under control, investigate whether Codex's built-in `Skill Creator` and `Plugin Creator` can help reduce maintenance or packaging friction for this repo.

- investigate programmatic `/goal` automation only if Codex exposes a stable CLI/API path; keep manual `/goal` guidance anchored to `$sdlc`
- evaluate `Skill Creator` as a possible future aid for skill-structure maintenance
- evaluate `Plugin Creator` only as later research, since plugins are not part of the current shipping path
- measure `gpt-5.4-mini` for the main working pass while keeping `gpt-5.5` `xhigh` for review or cross-model review, and compare that against simply running the whole slice at `xhigh`
- if the mixed mode proves out, add an easy toggle between two explicit profiles:
  - `mixed`: `gpt-5.4-mini` for the main pass plus `gpt-5.5` `xhigh` review
  - `maximum`: `gpt-5.5` / `xhigh` for the whole slice as the "ultimate mode"
- do not change the default based on anecdotes: require a sample of 20 slices before recommending `gpt-5.4-mini` + `gpt-5.5` `xhigh` review as the normal mode
- numeric target for recommending the mixed mode: at least 95% end-to-end success, follow-up rate <= 10%, and at least a 15% improvement in cycle time versus all-`xhigh`
- keep abstract, complex, or high-blast-radius work on `high`/`xhigh` by default until separate numbers say otherwise
- keep this behind the active workload so it does not compete with the active pilot-rollout and stabilization backlog
