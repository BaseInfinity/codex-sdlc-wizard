# Codex SDLC Wizard Roadmap

## Current State

- `codex-sdlc-wizard@0.5.0` and `v0.5.0` are the current release target for the repo-scoped Codex discovery bridge
- npm trusted publishing is configured and the GitHub release workflow is now proven for real OIDC publish
- the repo now ships both a Codex skill package (`SKILL.md`, `agents/openai.yaml`) and the installer/setup adapter (`install.sh`, `setup.sh`)
- the repo-scoped Codex discovery bridge for `$sdlc` / `$adlc` is now part of the shipping path
- consumer-path hardening for auth-heavy boundaries, capability detectors, and docs-strong scaffold repos is shipped
- benchmark and pilot-rollout ledgers now exist so model/default-use decisions can be measured, not guessed
- release, packaging, npm, skill, setup, adapter, and E2E tests are green

## Next Release Cycle

### 0.6.0

Purpose: tighten the remaining docs/process backlog after the consumer path and discovery bridge land.

Scope:
- work through `#7` to `#10`
- keep the honest Codex SDLC architecture explicit
- close the loop on confidence reporting, issue filing, and repo-focus guidance

## Tracker Cleanup

The issue tracker should be updated now that the discovery-bridge release is live.

- close `#14` Codex discovery bridge for `sdlc` / `adlc`
- review whether `#7` and `#8` should be closed as mostly shipped or narrowed to docs polish

## Remaining Backlog

After `0.5.0` and issue cleanup, the main backlog is:

- `#7` keep the honest Codex SDLC architecture explicit
- `#8` high-confidence slices and explicit confidence reporting
- `#9` prefer direct GitHub issue creation for proven reusable findings
- `#10` repo-focus rule so product work is not derailed by wizard fixes

## Working Order

1. Work through `#7` to `#10` as docs/process/product-shape improvements
2. Prove the default-use gate on 3-5 pilot repos
3. Keep creator-tool investigation behind the active backlog

## Default-Use Gate

Before calling this the default Codex SDLC path, prove it on real pilot repos instead of just repo-self-tests.

- run `0.5.0` on 3-5 pilot repos
- require pilot success >= 95% before default use
- allow no more than 1 reusable wizard bug across the pilot set
- track the pilot set in `benchmarks/pilot-rollout.csv`
- summarize the gate with `bash scripts/summarize-pilot-rollout.sh`

## Later Research

After the current backlog is under control, investigate whether Codex's built-in `Skill Creator` and `Plugin Creator` can help reduce maintenance or packaging friction for this repo.

- evaluate `Skill Creator` as a possible future aid for skill-structure maintenance
- evaluate `Plugin Creator` only as later research, since plugins are not part of the current shipping path
- experiment with `gpt-5.4-mini` for the main working pass while keeping `xhigh` for review or cross-model review, and compare that against simply running the whole slice at `xhigh`
- do not change the default based on anecdotes: require a sample of 20 slices before recommending `gpt-5.4-mini` + `xhigh` review as the normal mode
- numeric target for recommending the mixed mode: at least 95% end-to-end success, follow-up rate <= 10%, and at least a 15% improvement in cycle time versus all-`xhigh`
- keep abstract, complex, or high-blast-radius work on `high`/`xhigh` by default until separate numbers say otherwise
- keep this behind the active workload so it does not compete with `#14` or the `#4` to `#10` backlog
