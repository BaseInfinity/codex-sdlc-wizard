# Codex SDLC Wizard Roadmap

## How to use this roadmap

- GitHub issues are the source of truth for scope, acceptance criteria, milestone membership, and status.
- `ROADMAP.md` is this repository's single ordered project backlog and cold-session resume contract.
- The numbered order below is the project priority. The first open item is next unless the maintainer explicitly reorders the queue.
- A GitHub milestone is a planned release; its open issues are the work required before that release can close.
- An optional generated `GOALS.md` may scope execution inside a consumer repo, but it never overrides this project's priority queue.
- Remove completed issues from the queue, add every new actionable issue once, and keep every open issue assigned to a milestone.
- Pull requests reference their owning issue. Failing proof, review, or required CI never merges.

## Cold-session checkpoint — resume here

- The active engineering slice is [#172](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/172) in `/Users/stefanayala/codex-sdlc-issue172` on `fix/issue-172-fable-verdict-contract`, based on `2a682e2f4a5e31c503c32563efd87cf3fceac561`.
- Align the Fable prompt with the strict review validator: both independent and reconciliation prompts must name exact `CERTIFIED` / `NOT CERTIFIED` literals while aliases remain invalid and non-retryable.
- #157 is integrated through PR #166, #158 through PR #165, and #167 through PR #170. #158's one-time meta-review owner exception is consumed; do not reuse or broaden it. #167 passed normal Sol High plus Fable High review and both pre/post-merge Windows CI gates.
- #86 is parked at proven candidate tree `2e06247acd75b36dea95dd16d199e3f7d3b986be` after two Fable High attempts returned the unsupported `pass` alias. Neither attempt certified; do not retry or normalize the alias.
- Do not edit, stage, clean, or merge the dirty root checkout. It contains unrelated historical work.
- After #172 integrates, resume [#86](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/86) from a newly authorized current-main checkpoint. Then create a fresh authorized plan for the frozen [#109](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/109) v4 candidate; do not reuse consumed gate attempts or obsolete plans.
- Continue through the complete `1.0.0` block below. Do not start post-1.0 work while an earlier release blocker remains open.

## Current State

- Latest published GitHub release: [`v0.7.37`](https://github.com/BaseInfinity/codex-sdlc-wizard/releases/tag/v0.7.37).
- Latest published npm release: [`codex-sdlc-wizard@0.7.37`](https://www.npmjs.com/package/codex-sdlc-wizard/v/0.7.37).
- Development package metadata: `0.7.38`; it is not a published release.
- Next major release: [`1.0.0 — Bounded autonomous delivery`](https://github.com/BaseInfinity/codex-sdlc-wizard/milestone/2).
- The synchronized 1.0 milestone contains nine open release issues and fourteen completed issues as of 2026-08-23.
- The release objective is bounded autonomous delivery: exact-candidate proof, terminating independent review, honest failures, one canonical workflow entry, trustworthy Windows behavior, real Windows acceptance, and immutable publish verification.
- Real Windows Codex Desktop and CLI acceptance remains the final hardware-dependent gate before publish verification.
- `1.0.0` is the next public release. Do not divert the release train into another 0.7.x feature batch.

## Priority queue

1. **Require exact Fable verdict literals** — [#172: align the Fable prompt with the strict certifying-verdict contract](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/172) (`1.0.0`, P0, active).
2. **Enforce High-only autonomous Sol work** — [#86: remove autonomous xhigh escalation and the former maintainer exception](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/86) (`1.0.0`, P0, parked until #172 lands).
3. **Complete the measured bounded-correction pilot** — [#109: incremental corrective commits with a final whole-PR gate](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/109) (`1.0.0`, P0, frozen until #172 and #86 land).
4. **Block executable Git configuration at delivery** — [#141: reject exec-capable Git config in exact-candidate commands](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/141) (`1.0.0`).
5. **Restore one canonical workflow entry** — [#127: remove duplicate global and repo-local `$sdlc` exposure](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/127) (`1.0.0`).
6. **Eliminate nondeterministic Windows proof cleanup** — [#92: fix access-denied proof-stamp teardown](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/92) (`1.0.0`).
7. **Keep Windows review evidence honest** — [#93: detect WindowsApps PowerShell before trusting review validation](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/93) (`1.0.0`).
8. **Run the final real-Windows acceptance gate** — [#79: validate the 1.0 candidate in Codex Desktop and CLI](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/79) (`1.0.0`, human-required).
9. **Publish and verify the major release** — [#88: publish and verify `codex-sdlc-wizard` 1.0.0 across GitHub, npm, plugin, Codex Desktop, and Codex CLI surfaces](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/88) (`1.0.0`, human-required where credentials require it).
10. **Audit host-managed memory before premium rollout** — [#129: compare host memory with checked-in repository truth](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/129) (`1.1.0`).
11. **Implement the premium Codex host lane** — [#128: Fable High plans/reviews and Sol High builds with one reconciliation](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/128) (`1.1.0`).
12. **Make Fable review output evidence-first** — [#123: tighten cross-model review output](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/123) (`1.1.0`).
13. **Preserve known-good behavior during upgrades** — [#84: adopt a stability contract for model and harness changes](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/84) (`1.1.0`).
14. **Classify self-targeting maintenance as SDLC work** — [#130: treat mutating setup, update, and repair commands honestly](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/130) (`1.1.0`).
15. **Validate PowerShell policy before mutation** — [#153: reject invalid reviewer policy before updater writes](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/153) (`1.1.0`).
16. **Align skill metadata with evidence lanes** — [#154: make headings and descriptions honest](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/154) (`1.1.0`).
17. **Add one read-only health entrypoint** — [#82: implement a Codex-native doctor flow with explicit repair](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/82) (`1.1.0`).
18. **Audit generated instruction ownership** — [#95: reconcile `AGENTS.md` with current Codex guidance](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/95) (`1.1.0`).
19. **Make sibling harnesses coexist safely** — [#106: define shared-root ownership with `claude-sdlc-harness`](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/106) (`1.1.0`).
20. **Teach the issue-to-PR-to-release lifecycle** — [#100: enforce bounded issue, pull-request, milestone, and merge state](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/100) (`1.1.0`).
21. **Support ordered multi-milestone goals** — [#151: continue across ordered milestones and hand off cleanup safely](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/151) (`1.1.0`).
22. **Make terminal lifecycle state declarative** — [#136: reconcile exact status after merge](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/136) (`1.1.0`).
23. **Add an opt-in progress dashboard** — [#135: show issue and milestone progress without claiming readiness](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/135) (`1.1.0`).
24. **Preserve privacy in feedback attribution** — [#126: make source-repository attribution opt-in](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/126) (`1.1.0`).
25. **Soak the released contract in real consumer repos** — [#112: collect daily post-1.0 feedback and make only proven fixes](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/112) (`1.1.0`).
26. **Measure adversarial refutation against bounded review** — [#138: compare cross-vendor review strategies](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/138) (`1.1.0`, research).
27. **Research convergence-based termination** — [#132: compare convergence with fixed correction caps](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/132) (`1.1.0`, research).
28. **Retain concise failed-proof evidence** — [#124: preserve failed-test summaries when broad proof output truncates](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/124) (`1.1.0`).
29. **Separate confidence from defect severity** — [#131: require actionable reviewer remediation without conflating confidence](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/131) (`1.1.0`).
30. **Make explicit updates one-step and agent-driven** — [#147: honor requests to update to the latest wizard](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/147) (`1.1.0`).
31. **Make after-hours Windows pushes guard-compatible** — [#162: provide an explicit safe push override path](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/162) (`1.1.0`).
32. **Emit bounded provider progress during reviews** — [#164: expose long-running dual-review progress](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/164) (`1.1.0`).
33. **Harden standalone Fable supervision** — [#171: bound standalone Fable process trees and bind review-run identity](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/171) (`1.1.0`).
34. **Research a fast incremental model lane** — [#114: evaluate GPT-5.3-Codex-Spark](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/114) (`1.2.0`).
35. **Benchmark optional worker orchestration** — [#72: compare direct Sol driving with bounded Luna workers](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/72) (`1.2.0`).
36. **Research context-pressure policy** — [#77: measure compaction thresholds and worker effects](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/77) (`1.2.0`).
37. **Submit the proven release to the Plugins Directory** — [#66: complete universal directory submission](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/66) (`Distribution`, human-required).
38. **Research recurring post-1.0 distribution** — [#140: evaluate agent marketplaces and directories](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/140) (`Distribution`, research).
39. **Audit CI/CD for independent value** — [#108: retain only release-enforcing evidence](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/108) (`1.3.0`).
40. **Prove fast-first without weakening full-final** — [#139: evaluate a bounded CI tier](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/139) (`1.3.0`, research).
41. **Detect release drift deterministically** — [#99: reconcile package, tag, release, and issue state](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/99) (`1.3.0`).
42. **Timebox the cumulative upstream audit** — [#65: evaluate upstream v1.74.0 through v1.91.0](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/65) (`1.3.0`).
43. **Reconcile upstream v1.96.0** — [#113: evaluate the newer SDLC Wizard release](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/113) (`1.3.0`).
44. **Reconcile upstream v1.98.0** — [#160: translate applicable upstream changes](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/160) (`1.3.0`).
45. **Keep release documentation impact-based** — [#105: add stabilized demos only when they materially help](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/105) (`1.4.0`).
46. **Consolidate redundant proof documentation** — [#104: fold `PROVE-IT.md` into `TESTING.md` by default](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/104) (`1.4.0`).
47. **Rename wizard to harness with a controlled migration** — [#101: apply the sibling-repo migration checklist safely](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/101) (`1.4.0`).
48. **Clean contributor attribution only through an explicit history operation** — [#107: remove bot attribution without risking repository history](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/107) (`1.4.0`, human-required).
49. **Research persistent Codex output style** — [#144: identify and measure the nearest supported mechanism](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/144) (`Research`, non-blocking).
50. **Research DeepSeek Harness after 1.0** — [#142: evaluate portable plugin ideas](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/142) (`Research`, non-blocking).
51. **Track the in-app Browser range-slider defect** — [#134: require observable native slider interaction](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/134) (`Research`, external-tooling, non-blocking).
52. **Map the SDLC experience across Copilot tiers** — [#125: compare every Copilot host](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/125) (`Research`, non-blocking).
53. **Identify the Microsoft-enterprise coding host** — [#122: prove the supported enterprise surface](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/122) (`Research`, human-required, non-blocking).
54. **Evaluate another CLI host** — [#97: research a GitHub Copilot CLI adapter](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/97) (`Research`, non-blocking).
55. **Revisit portable enforcement after host adapters stabilize** — [#58: compare a portable SDLC MCP server with per-host skills](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/58) (`Research`, non-blocking).
56. **Decide the Copilot Studio adoption path** — [#96: research a front end only after portable enforcement is justified](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/96) (`Research`, human-required, non-blocking).
57. **Keep Copilot Studio implementation contingent** — [#163: build and E2E-test the agent only after #96 selects adoption or experiment](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/163) (`Research`, contingent, non-blocking).
