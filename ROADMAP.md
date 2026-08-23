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

- The active engineering slice is [#175](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/175) in `/Users/stefanayala/codex-sdlc-issue175` on `fix/issue-175-final-fable-response`, based on current `origin/main` at `b7c8d4590a483afa0be61f1bb9ed4408d3b520cd`.
- Tell tool-free Fable to return one immediate final schema-valid JSON review from the complete supplied evidence; the runtime guarantee remains strict rejection and a non-certifying receipt for deferral, narration, or any other invalid output.
- #157 is integrated through PR #166, #158 through PR #165, #167 through PR #170, and #172 through PR #173. #158's one-time meta-review owner exception is consumed; do not reuse or broaden it. Required pre/post-merge Windows CI passed for the integrated slices.
- #174 is frozen at candidate tree `2636c7da25fcd9a19735112f938e050981012a6c`. Canonical proof passed 11/11, but Fable returned only repository-inspection deferral prose; the strict gate wrote a non-certifying `invalid_execution` receipt, cancelled incomplete Sol, and recommends no retry.
- #86 is frozen at final candidate tree `7cfa28ec0add78c706cd24f28b15a9e9e99d023b`. Canonical proof passed 11/11, but normal Sol High plus Fable High review converged on the #174 P1, so its receipt is non-certifying and the candidate must not be delivered or retried.
- Do not edit, stage, clean, or merge the dirty root checkout. It contains unrelated historical work.
- After #175 integrates, resume [#174](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/174) from a fresh current-main worktree and fresh proof/review candidate. Then resume [#86](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/86), followed by a fresh authorized plan for frozen [#109](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/109) v4; do not reuse consumed gate attempts or obsolete plans.
- Continue through the complete `1.0.0` block below. Do not start post-1.0 work while an earlier release blocker remains open.

## Current State

- Latest published GitHub release: [`v0.7.37`](https://github.com/BaseInfinity/codex-sdlc-wizard/releases/tag/v0.7.37).
- Latest published npm release: [`codex-sdlc-wizard@0.7.37`](https://www.npmjs.com/package/codex-sdlc-wizard/v/0.7.37).
- Development package metadata: `0.7.38`; it is not a published release.
- Next major release: [`1.0.0 — Bounded autonomous delivery`](https://github.com/BaseInfinity/codex-sdlc-wizard/milestone/2).
- The synchronized 1.0 milestone contains ten open release issues and fifteen completed issues as of 2026-08-23.
- The release objective is bounded autonomous delivery: exact-candidate proof, terminating independent review, honest failures, one canonical workflow entry, trustworthy Windows behavior, real Windows acceptance, and immutable publish verification.
- Real Windows Codex Desktop and CLI acceptance remains the final hardware-dependent gate before publish verification.
- `1.0.0` is the next public release. Do not divert the release train into another 0.7.x feature batch.

## Priority queue

1. **Reduce tool-free Fable deferral and fail closed** — [#175: instruct immediate review JSON and reject every invalid response](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/175) (`1.0.0`, P0, active).
2. **Keep model-policy migration claims truthful** — [#174: leave migration pending while preserved guidance still authorizes autonomous xhigh](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/174) (`1.0.0`, P0, frozen until #175 lands).
3. **Enforce High-only autonomous Sol work** — [#86: remove autonomous xhigh escalation and the former maintainer exception](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/86) (`1.0.0`, P0, frozen until #174 lands).
4. **Complete the measured bounded-correction pilot** — [#109: incremental corrective commits with a final whole-PR gate](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/109) (`1.0.0`, P0, frozen until #174 and #86 land).
5. **Block executable Git configuration at delivery** — [#141: reject exec-capable Git config in exact-candidate commands](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/141) (`1.0.0`).
6. **Restore one canonical workflow entry** — [#127: remove duplicate global and repo-local `$sdlc` exposure](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/127) (`1.0.0`).
7. **Eliminate nondeterministic Windows proof cleanup** — [#92: fix access-denied proof-stamp teardown](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/92) (`1.0.0`).
8. **Keep Windows review evidence honest** — [#93: detect WindowsApps PowerShell before trusting review validation](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/93) (`1.0.0`).
9. **Run the final real-Windows acceptance gate** — [#79: validate the exact 1.0 candidate in Codex Desktop and CLI, including observed config/picker precedence](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/79) (`1.0.0`, human-required).
10. **Publish and verify the major release** — [#88: publish and verify `codex-sdlc-wizard` 1.0.0 across GitHub, npm, plugin, Codex Desktop, and Codex CLI surfaces](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/88) (`1.0.0`, human-required where credentials require it).
11. **Audit host-managed memory before premium rollout** — [#129: compare host memory with checked-in repository truth](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/129) (`1.1.0`).
12. **Implement the premium Codex host lane** — [#128: Fable High plans/reviews and Sol High builds with one reconciliation](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/128) (`1.1.0`).
13. **Make Fable review output evidence-first** — [#123: tighten cross-model review output](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/123) (`1.1.0`).
14. **Preserve known-good behavior during upgrades** — [#84: adopt a stability contract for model and harness changes](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/84) (`1.1.0`).
15. **Classify self-targeting maintenance as SDLC work** — [#130: treat mutating setup, update, and repair commands honestly](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/130) (`1.1.0`).
16. **Validate PowerShell policy before mutation** — [#153: reject invalid reviewer policy before updater writes](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/153) (`1.1.0`).
17. **Align skill metadata with evidence lanes** — [#154: make headings and descriptions honest](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/154) (`1.1.0`).
18. **Add one read-only health entrypoint** — [#82: implement a Codex-native doctor flow with explicit repair](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/82) (`1.1.0`).
19. **Audit generated instruction ownership** — [#95: reconcile `AGENTS.md` with current Codex guidance](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/95) (`1.1.0`).
20. **Make sibling harnesses coexist safely** — [#106: define shared-root ownership with `claude-sdlc-harness`](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/106) (`1.1.0`).
21. **Teach the issue-to-PR-to-release lifecycle** — [#100: enforce bounded issue, pull-request, milestone, and merge state](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/100) (`1.1.0`).
22. **Support ordered multi-milestone goals** — [#151: continue across ordered milestones and hand off cleanup safely](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/151) (`1.1.0`).
23. **Make terminal lifecycle state declarative** — [#136: reconcile exact status after merge](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/136) (`1.1.0`).
24. **Add an opt-in progress dashboard** — [#135: show issue and milestone progress without claiming readiness](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/135) (`1.1.0`).
25. **Preserve privacy in feedback attribution** — [#126: make source-repository attribution opt-in](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/126) (`1.1.0`).
26. **Soak the released contract in real consumer repos** — [#112: collect daily post-1.0 feedback and make only proven fixes](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/112) (`1.1.0`).
27. **Measure adversarial refutation against bounded review** — [#138: compare cross-vendor review strategies](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/138) (`1.1.0`, research).
28. **Research convergence-based termination** — [#132: compare convergence with fixed correction caps](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/132) (`1.1.0`, research).
29. **Retain concise failed-proof evidence** — [#124: preserve failed-test summaries when broad proof output truncates](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/124) (`1.1.0`).
30. **Separate confidence from defect severity** — [#131: require actionable reviewer remediation without conflating confidence](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/131) (`1.1.0`).
31. **Make explicit updates one-step and agent-driven** — [#147: honor requests to update to the latest wizard](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/147) (`1.1.0`).
32. **Make after-hours Windows pushes guard-compatible** — [#162: provide an explicit safe push override path](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/162) (`1.1.0`).
33. **Emit bounded provider progress during reviews** — [#164: expose long-running dual-review progress](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/164) (`1.1.0`).
34. **Harden standalone Fable supervision** — [#171: bound standalone Fable process trees and bind review-run identity](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/171) (`1.1.0`).
35. **Track third-party release provenance** — [#168: add third-party asset provenance to release preflight](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/168) (`1.1.0`).
36. **Research a fast incremental model lane** — [#114: evaluate GPT-5.3-Codex-Spark](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/114) (`1.2.0`).
37. **Benchmark optional worker orchestration** — [#72: compare direct Sol driving with bounded Luna workers](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/72) (`1.2.0`).
38. **Research context-pressure policy** — [#77: measure compaction thresholds and worker effects](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/77) (`1.2.0`).
39. **Submit the proven release to the Plugins Directory** — [#66: complete universal directory submission](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/66) (`Distribution`, human-required).
40. **Research recurring post-1.0 distribution** — [#140: evaluate agent marketplaces and directories](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/140) (`Distribution`, research).
41. **Audit CI/CD for independent value** — [#108: retain only release-enforcing evidence](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/108) (`1.3.0`).
42. **Prove fast-first without weakening full-final** — [#139: evaluate a bounded CI tier](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/139) (`1.3.0`, research).
43. **Detect release drift deterministically** — [#99: reconcile package, tag, release, and issue state](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/99) (`1.3.0`).
44. **Timebox the cumulative upstream audit** — [#65: evaluate upstream v1.74.0 through v1.91.0](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/65) (`1.3.0`).
45. **Reconcile upstream v1.96.0** — [#113: evaluate the newer SDLC Wizard release](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/113) (`1.3.0`).
46. **Reconcile upstream v1.98.0** — [#160: translate applicable upstream changes](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/160) (`1.3.0`).
47. **Keep release documentation impact-based** — [#105: add stabilized demos only when they materially help](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/105) (`1.4.0`).
48. **Consolidate redundant proof documentation** — [#104: fold `PROVE-IT.md` into `TESTING.md` by default](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/104) (`1.4.0`).
49. **Rename wizard to harness with a controlled migration** — [#101: apply the sibling-repo migration checklist safely](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/101) (`1.4.0`).
50. **Clean contributor attribution only through an explicit history operation** — [#107: remove bot attribution without risking repository history](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/107) (`1.4.0`, human-required).
51. **Research persistent Codex output style** — [#144: identify and measure the nearest supported mechanism](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/144) (`Research`, non-blocking).
52. **Research DeepSeek Harness after 1.0** — [#142: evaluate portable plugin ideas](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/142) (`Research`, non-blocking).
53. **Track the in-app Browser range-slider defect** — [#134: require observable native slider interaction](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/134) (`Research`, external-tooling, non-blocking).
54. **Map the SDLC experience across Copilot tiers** — [#125: compare every Copilot host](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/125) (`Research`, non-blocking).
55. **Identify the Microsoft-enterprise coding host** — [#122: prove the supported enterprise surface](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/122) (`Research`, human-required, non-blocking).
56. **Evaluate another CLI host** — [#97: research a GitHub Copilot CLI adapter](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/97) (`Research`, non-blocking).
57. **Revisit portable enforcement after host adapters stabilize** — [#58: compare a portable SDLC MCP server with per-host skills](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/58) (`Research`, non-blocking).
58. **Decide the Copilot Studio adoption path** — [#96: research a front end only after portable enforcement is justified](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/96) (`Research`, human-required, non-blocking).
59. **Keep Copilot Studio implementation contingent** — [#163: build and E2E-test the agent only after #96 selects adoption or experiment](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/163) (`Research`, contingent, non-blocking).
60. **Release the post-1.0 Copilot adapter** — [#169: build and release the GitHub Copilot SDLC harness after 1.0](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/169) (`Research`, post-1.0, non-blocking).
