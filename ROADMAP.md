# Codex SDLC Wizard Roadmap

## Current State

- `codex-sdlc-wizard@0.6.0` and `v0.6.0` are the current release target for the docs/process hardening pass
- npm trusted publishing is configured and the GitHub release workflow is now proven for real OIDC publish
- the repo now ships both a Codex skill package (`SKILL.md`, `agents/openai.yaml`) and the installer/setup adapter (`install.sh`, `setup.sh`)
- the repo-scoped Codex discovery bridge for `$sdlc` / `$adlc` is now part of the shipping path
- consumer-path hardening for auth-heavy boundaries, capability detectors, and docs-strong scaffold repos is shipped
- honest Codex architecture guidance, confidence/reporting guidance, direct-issue capture, and repo-focus rules are now part of the shipped path
- the model-profile toggle is now shipped as a user choice:
  - `mixed`: `gpt-5.4-mini` main pass + `xhigh` review
  - `maximum`: `gpt-5.4` / `xhigh` throughout
- benchmark and pilot-rollout ledgers now exist so model/default-use decisions can be measured, not guessed
- release, packaging, npm, skill, setup, adapter, and E2E tests are green

## Next Release Cycle

### 0.6.1

Purpose: prove the post-`0.6.0` consumer path on real repos and stabilize any reusable wizard bugs without changing the default-use claim early.

Scope:
- run `0.6.0` on 3-5 pilot repos and log results in `benchmarks/pilot-rollout.csv`
- cut a stabilization patch only if pilots surface a reusable wizard bug
- keep the default-use recommendation gated on the measurable pilot summary
- keep the separate model experiment running, but do not let it block pilot rollout work

## Tracker Cleanup

The issue tracker should be updated as the 0.6.0 docs/process backlog lands.

- close or narrow `#7` once the honest Codex shape is explicit everywhere
- close or narrow `#8` once confidence reporting and slice-sizing guidance are explicit
- close or narrow `#9` once the feedback flow prefers direct GitHub issue capture
- close or narrow `#10` once the repo-focus rule is explicit in the shipped guidance

## Remaining Backlog

After `0.6.0` and issue cleanup, the main backlog is:

- pilot rollout proof for default use on real repos
- any reusable wizard fixes discovered during the pilot set
- model experiment data collection for `mixed` vs `maximum`
- later creator-tool research after the active backlog stays under control

## Working Order

1. Close or narrow `#7` to `#10` so the tracker matches the shipped guidance
2. Prove the default-use gate on 3-5 pilot repos with `0.6.0`
3. Ship `0.6.1` only if pilot rollout surfaces a reusable wizard bug
4. Keep creator-tool investigation behind the active backlog

## Default-Use Gate

Before calling this the default Codex SDLC path, prove it on real pilot repos instead of just repo-self-tests.

- run `0.6.0` on 3-5 pilot repos
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
- keep this behind the active workload so it does not compete with the `#7` to `#10` backlog
