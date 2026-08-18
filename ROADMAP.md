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

- The active engineering slice is [#158](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/158) in `/private/tmp/codex-sdlc-issue158` on `fix/issue-158-reject-review-tools`.
- Its staged candidate tree `f43b24de8058b9a97e8ac009b7718ccb66361b3b` passed focused proof and the canonical 11/11 proof, then correctly returned `NOT CERTIFIED`.
- The blocking findings are candidate-born: detect real nested Claude `message.content[]` tool-use blocks, prevent a rejected event from becoming a clean result, and keep rejection classification ahead of timeout classification.
- Add focused RED regressions for those behaviors, implement one bounded corrective slice, rerun focused proof, mint one fresh canonical proof, and run one bounded completion gate.
- Do not edit, stage, clean, or merge the dirty root checkout. It contains unrelated historical work.
- After #158 integrates, return to the frozen [#109](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/109) v4 pilot. Do not resume its obsolete v2 or v3 candidates.
- Continue through the complete `1.0.0` block below. Do not start post-1.0 work while an earlier release blocker remains open.

## Current State

- Latest published GitHub release: [`v0.7.37`](https://github.com/BaseInfinity/codex-sdlc-wizard/releases/tag/v0.7.37).
- Latest published npm release: [`codex-sdlc-wizard@0.7.37`](https://www.npmjs.com/package/codex-sdlc-wizard/v/0.7.37).
- Development package metadata: `0.7.38`; it is not a published release.
- Next major release: [`1.0.0 — Bounded autonomous delivery`](https://github.com/BaseInfinity/codex-sdlc-wizard/milestone/2).
- The synchronized 1.0 milestone contains twelve open release issues and eleven completed issues as of 2026-08-17.
- The release objective is bounded autonomous delivery: exact-candidate proof, terminating independent review, honest failures, one canonical workflow entry, trustworthy Windows behavior, real Windows acceptance, and immutable publish verification.
- Real Windows Codex Desktop and CLI acceptance remains the final hardware-dependent gate before publish verification.
- `1.0.0` is the next public release. Do not divert the release train into another 0.7.x feature batch.

## Priority queue

1. **Reject forbidden reviewer tool use immediately** — [#158: stop tool-free cross-model reviews when Claude invokes advisor](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/158) (`1.0.0`, P0, active).
2. **Complete the measured bounded-correction pilot** — [#109: incremental corrective commits with a final whole-PR gate](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/109) (`1.0.0`, P0).
3. **Make reviewer infrastructure state observable** — [#157: expose provider progress and distinguish invocation failure from verdict](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/157) (`1.0.0`).
4. **Block executable Git configuration at delivery** — [#141: reject exec-capable Git config in exact-candidate commands](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/141) (`1.0.0`).
5. **Separate confidence from defect severity** — [#131: require actionable reviewer remediation without conflating confidence](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/131) (`1.0.0`).
6. **Retain concise failed-proof evidence** — [#124: preserve failed-test summaries when broad proof output truncates](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/124) (`1.0.0`).
7. **Restore one canonical workflow entry** — [#127: remove duplicate global and repo-local `$sdlc` exposure](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/127) (`1.0.0`).
8. **Make explicit updates one-step and agent-driven** — [#147: honor requests to update to the latest wizard](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/147) (`1.0.0`).
9. **Eliminate nondeterministic Windows proof cleanup** — [#92: fix access-denied proof-stamp teardown](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/92) (`1.0.0`).
10. **Keep Windows review evidence honest** — [#93: detect WindowsApps PowerShell before trusting review validation](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/93) (`1.0.0`).
11. **Run the final real-Windows acceptance gate** — [#79: validate the 1.0 candidate in Codex Desktop and CLI](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/79) (`1.0.0`, human-required).
12. **Publish and verify the major release** — [#88: publish `codex-sdlc-wizard` 1.0.0 to npm and GitHub](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/88) (`1.0.0`, human-required where credentials require it).
13. **Audit host-managed memory before premium rollout** — [#129: compare host memory with checked-in repository truth](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/129) (`1.1.0`).
14. **Implement the premium Codex host lane** — [#128: Fable High plans/reviews and Sol High builds with one reconciliation](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/128) (`1.1.0`).
15. **Finish the High-only planning and review policy** — [#86: preserve explicit implementation overrides](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/86) (`1.1.0`).
16. **Make Fable review output evidence-first** — [#123: tighten cross-model review output](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/123) (`1.1.0`).
17. **Preserve known-good behavior during upgrades** — [#84: adopt a stability contract for model and harness changes](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/84) (`1.1.0`).
18. **Classify self-targeting maintenance as SDLC work** — [#130: treat mutating setup, update, and repair commands honestly](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/130) (`1.1.0`).
19. **Validate PowerShell policy before mutation** — [#153: reject invalid reviewer policy before updater writes](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/153) (`1.1.0`).
20. **Align skill metadata with evidence lanes** — [#154: make headings and descriptions honest](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/154) (`1.1.0`).
21. **Add one read-only health entrypoint** — [#82: implement a Codex-native doctor flow with explicit repair](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/82) (`1.1.0`).
22. **Audit generated instruction ownership** — [#95: reconcile `AGENTS.md` with current Codex guidance](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/95) (`1.1.0`).
23. **Make sibling harnesses coexist safely** — [#106: define shared-root ownership with `claude-sdlc-harness`](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/106) (`1.1.0`).
24. **Teach the issue-to-PR-to-release lifecycle** — [#100: enforce bounded issue, pull-request, milestone, and merge state](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/100) (`1.1.0`).
25. **Support ordered multi-milestone goals** — [#151: continue across ordered milestones and hand off cleanup safely](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/151) (`1.1.0`).
26. **Make terminal lifecycle state declarative** — [#136: reconcile exact status after merge](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/136) (`1.1.0`).
27. **Add an opt-in progress dashboard** — [#135: show issue and milestone progress without claiming readiness](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/135) (`1.1.0`).
28. **Preserve privacy in feedback attribution** — [#126: make source-repository attribution opt-in](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/126) (`1.1.0`).
29. **Soak the released contract in real consumer repos** — [#112: collect daily post-1.0 feedback and make only proven fixes](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/112) (`1.1.0`).
30. **Measure adversarial refutation against bounded review** — [#138: compare cross-vendor review strategies](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/138) (`1.1.0`, research).
31. **Research convergence-based termination** — [#132: compare convergence with fixed correction caps](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/132) (`1.1.0`, research).
32. **Research a fast incremental model lane** — [#114: evaluate GPT-5.3-Codex-Spark](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/114) (`1.2.0`).
33. **Benchmark optional worker orchestration** — [#72: compare direct Sol driving with bounded Luna workers](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/72) (`1.2.0`).
34. **Research context-pressure policy** — [#77: measure compaction thresholds and worker effects](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/77) (`1.2.0`).
35. **Submit the proven release to the Plugins Directory** — [#66: complete universal directory submission](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/66) (`Distribution`, human-required).
36. **Research recurring post-1.0 distribution** — [#140: evaluate agent marketplaces and directories](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/140) (`Distribution`, research).
37. **Audit CI/CD for independent value** — [#108: retain only release-enforcing evidence](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/108) (`1.3.0`).
38. **Prove fast-first without weakening full-final** — [#139: evaluate a bounded CI tier](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/139) (`1.3.0`, research).
39. **Detect release drift deterministically** — [#99: reconcile package, tag, release, and issue state](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/99) (`1.3.0`).
40. **Timebox the cumulative upstream audit** — [#65: evaluate upstream v1.74.0 through v1.91.0](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/65) (`1.3.0`).
41. **Reconcile upstream v1.96.0** — [#113: evaluate the newer SDLC Wizard release](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/113) (`1.3.0`).
42. **Reconcile upstream v1.98.0** — [#160: translate applicable upstream changes](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/160) (`1.3.0`).
43. **Keep release documentation impact-based** — [#105: add stabilized demos only when they materially help](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/105) (`1.4.0`).
44. **Consolidate redundant proof documentation** — [#104: fold `PROVE-IT.md` into `TESTING.md` by default](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/104) (`1.4.0`).
45. **Rename wizard to harness with a controlled migration** — [#101: apply the sibling-repo migration checklist safely](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/101) (`1.4.0`).
46. **Clean contributor attribution only through an explicit history operation** — [#107: remove bot attribution without risking repository history](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/107) (`1.4.0`, human-required).
47. **Research persistent Codex output style** — [#144: identify and measure the nearest supported mechanism](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/144) (`Research`, non-blocking).
48. **Research DeepSeek Harness after 1.0** — [#142: evaluate portable plugin ideas](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/142) (`Research`, non-blocking).
49. **Track the in-app Browser range-slider defect** — [#134: require observable native slider interaction](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/134) (`Research`, external-tooling, non-blocking).
50. **Map the SDLC experience across Copilot tiers** — [#125: compare every Copilot host](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/125) (`Research`, non-blocking).
51. **Identify the Microsoft-enterprise coding host** — [#122: prove the supported enterprise surface](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/122) (`Research`, human-required, non-blocking).
52. **Evaluate another CLI host** — [#97: research a GitHub Copilot CLI adapter](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/97) (`Research`, non-blocking).
53. **Revisit portable enforcement after host adapters stabilize** — [#58: compare a portable SDLC MCP server with per-host skills](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/58) (`Research`, non-blocking).
54. **Consider a Copilot Studio surface last** — [#96: research a front end only after portable enforcement is justified](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/96) (`Research`, human-required, non-blocking).
