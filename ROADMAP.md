# Codex SDLC Wizard Roadmap

## Current State

- `codex-sdlc-wizard@0.7.4` and `v0.7.4` are the current release target for the xhigh conversational setup refinement pass
- npm trusted publishing is configured and the GitHub release workflow is now proven for real OIDC publish
- the repo now ships both a Codex skill package (`SKILL.md`, `agents/openai.yaml`) and the installer/setup adapter (`install.sh`, `setup.sh`)
- the npm CLI now defaults to adaptive interactive setup instead of requiring an explicit `setup` subcommand for the main human path
- setup now layers deterministic scan plus live Codex `gpt-5.4` / `xhigh` refinement when available
- setup now keeps detected values automatically, asks inferred values conversationally, and asks only missing core repo facts directly
- the repo-scoped Codex discovery bridge for `$sdlc` / `$adlc` is now part of the shipping path
- consumer-path hardening for auth-heavy boundaries, capability detectors, and docs-strong scaffold repos is shipped
- honest Codex architecture guidance, confidence/reporting guidance, direct-issue capture, and repo-focus rules are now part of the shipped path
- the model-profile toggle is now shipped as a user choice:
  - `mixed`: `gpt-5.4-mini` main pass + `xhigh` review
  - `maximum`: `gpt-5.4` / `xhigh` throughout
- setup/install now offer issue-ready feedback for obvious wizard-level failures instead of only failing vaguely
- setup/update guidance now biases bootstrap work toward `maximum` while routine work can switch back to `mixed`
- the repo now ships a consumer bug-report template for install/setup/runtime failures
- the public README now leads with the real `@latest` adaptive setup path and keeps the top section consumer-focused
- benchmark and pilot-rollout ledgers now exist so model/default-use decisions can be measured, not guessed
- release, packaging, npm, skill, setup, adapter, update, and E2E tests are green when the parity merge is complete

## Next Release Cycle

### 0.7.5

Purpose: prove the post-`0.7.4` consumer path on real repos and stabilize any reusable wizard bugs without changing the default-use claim early.

Scope:
- run `0.7.4` on 3-5 pilot repos and log results in `benchmarks/pilot-rollout.csv`
- cut a stabilization patch only if pilots surface another reusable wizard bug
- keep the default-use recommendation gated on the measurable pilot summary
- keep the separate model experiment running, but do not let it block pilot rollout work

## Tracker Cleanup

The issue tracker is currently clear.

- open a new issue only when pilot consumption exposes a proven reusable wizard bug
- avoid speculative backlog churn while `0.7.4` is being consumed on real repos

## Remaining Backlog

After `0.7.4`, the main backlog is:

- pilot rollout proof for default use on real repos
- any reusable wizard fixes discovered during the pilot set
- model experiment data collection for `mixed` vs `maximum`
- later creator-tool research after the active backlog stays under control

## Working Order

1. Prove the default-use gate on 3-5 pilot repos with `0.7.4`
2. Ship `0.7.5` only if pilot rollout surfaces another reusable wizard bug
3. Keep creator-tool investigation behind the active backlog

## Default-Use Gate

Before calling this the default Codex SDLC path, prove it on real pilot repos instead of just repo-self-tests.

- run `0.7.4` on 3-5 pilot repos
- require pilot success >= 95% before default use
- allow no more than 1 reusable wizard bug across the pilot set
- track the pilot set in `benchmarks/pilot-rollout.csv`
- summarize the gate with `bash scripts/summarize-pilot-rollout.sh`

## Later Research

After the current backlog is under control, investigate whether Codex's built-in `Skill Creator` and `Plugin Creator` can help reduce maintenance or packaging friction for this repo.

- evaluate `Skill Creator` as a possible future aid for skill-structure maintenance
- evaluate `Plugin Creator` only as later research, since plugins are not part of the current shipping path
- experiment with `gpt-5.4-mini` for the main working pass while keeping `xhigh` for review or cross-model review, and compare that against simply running the whole slice at `xhigh`
- if the mixed mode proves out, add an easy toggle between two explicit profiles:
  - `mixed`: `gpt-5.4-mini` for the main pass plus `xhigh` review
  - `maximum`: `gpt-5.4` / `xhigh` for the whole slice as the "ultimate mode"
- do not change the default based on anecdotes: require a sample of 20 slices before recommending `gpt-5.4-mini` + `xhigh` review as the normal mode
- numeric target for recommending the mixed mode: at least 95% end-to-end success, follow-up rate <= 10%, and at least a 15% improvement in cycle time versus all-`xhigh`
- keep abstract, complex, or high-blast-radius work on `high`/`xhigh` by default until separate numbers say otherwise
- keep this behind the active workload so it does not compete with the active pilot-rollout and stabilization backlog
