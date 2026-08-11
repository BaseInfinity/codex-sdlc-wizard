# Codex SDLC Wizard Roadmap

## How to use this roadmap

- GitHub issues are the source of truth for scope, acceptance criteria, milestones, and status.
- The numbered order below is the project priority. The first open item is next unless the maintainer explicitly reorders the queue.
- A GitHub milestone is a planned release; its issues are the work required for that release.
- `ROADMAP.md` is this repository's single ordered project backlog. An optional generated `GOALS.md` may scope execution inside a consumer repo, but it never overrides this project's priority queue.
- Reorder links here when priority changes, but keep implementation detail and completion evidence in the linked issue or pull request.
- Every actionable item must have one issue owner. Pull requests reference or close that issue, and failing CI never merges.

## Current State

- Current GitHub release: [`v0.7.35`](https://github.com/BaseInfinity/codex-sdlc-wizard/releases/tag/v0.7.35).
- Current npm release: [`codex-sdlc-wizard@0.7.35`](https://www.npmjs.com/package/codex-sdlc-wizard/v/0.7.35).
- Next release milestone: [`1.0.0 — Bounded autonomous delivery`](https://github.com/BaseInfinity/codex-sdlc-wizard/milestone/2).
- The ten-delivery cadence pilot is installed on `main`; its measurement issue remains open until the recorded evidence supports a permanent policy.
- Real Windows Codex Desktop and CLI acceptance is the last hardware-dependent gate. Mac/Linux implementation and proof continue before that handoff.

## Priority queue

1. **Make two-reviewer reconciliation direct and bounded** — [#116: independent review, verbatim cross-feed, one reconciliation, one answer](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/116) (`1.0.0`).
2. **Bind final approval to the exact integrated candidate** — [#111: certify the precise tree that can reach the default branch](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/111) (`1.0.0`).
3. **Require honest RED evidence without manufacturing fake tests** — [#115: scope TDD RED to writable behavior and explicit evidence exceptions](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/115) (`1.0.0`).
4. **Measure the bounded incremental-review pilot** — [#109: record ten eligible deliveries and decide the permanent cadence empirically](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/109) (`1.0.0`).
5. **Eliminate nondeterministic Windows proof cleanup** — [#92: fix access-denied proof-stamp teardown](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/92) (`1.0.0`).
6. **Keep Windows review evidence honest** — [#93: detect WindowsApps PowerShell before trusting review validation](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/93) (`1.0.0`).
7. **Run the final real-Windows acceptance gate** — [#79: validate the 1.0 candidate in Codex Desktop and CLI](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/79) (`1.0.0`, human-required).
8. **Publish and verify the aligned release** — [#88: publish `codex-sdlc-wizard` 1.0.0 to npm and GitHub](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/88) (`1.0.0`, human-required where credentials require it).
9. **Soak the released contract in real consumer repos** — [#112: collect daily post-1.0 feedback and make only proven fixes](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/112) (`1.1.0`).
10. **Preserve known-good behavior during upgrades** — [#84: adopt a stability contract for model and harness changes](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/84) (`1.1.0`).
11. **Finish the Sol High policy migration** — [#86: enforce Sol High unless the user explicitly overrides it](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/86) (`1.1.0`).
12. **Audit generated instruction ownership** — [#95: reconcile `AGENTS.md` with current Codex guidance](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/95) (`1.1.0`).
13. **Teach the issue-to-PR-to-release lifecycle** — [#100: enforce bounded issue, pull-request, milestone, and merge state](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/100) (`1.1.0`).
14. **Make sibling harnesses coexist safely** — [#106: define shared-root ownership with `claude-sdlc-harness`](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/106) (`1.1.0`).
15. **Add one read-only health entrypoint** — [#82: implement a Codex-native doctor flow with explicit repair](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/82) (`1.1.0`).
16. **Submit the proven release to the Plugins Directory** — [#66: complete the universal directory submission](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/66) (`Distribution`).
17. **Audit CI/CD for independent value** — [#108: remove duplicate work and retain only release-enforcing evidence](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/108) (`1.2.0`).
18. **Detect release drift deterministically** — [#99: reconcile package, tag, release, and issue state](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/99) (`1.2.0`).
19. **Timebox the cumulative upstream audit** — [#65: evaluate upstream v1.74.0 through v1.91.0](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/65) (`1.2.0`).
20. **Reconcile the newest upstream release** — [#113: evaluate upstream SDLC Wizard v1.96.0](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/113) (`1.2.0`).
21. **Keep release documentation impact-based** — [#105: update README/release docs and add stabilized demos when they materially help](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/105) (`1.3.0`).
22. **Consolidate redundant proof documentation** — [#104: fold `PROVE-IT.md` into `TESTING.md` by default](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/104) (`1.3.0`).
23. **Rename wizard to harness with a controlled migration** — [#101: apply the sibling-repo migration checklist without breaking consumers](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/101) (`1.3.0`).
24. **Clean contributor attribution only through an explicit history operation** — [#107: remove bot attribution without risking repository history](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/107) (`1.3.0`, human-required).
25. **Research a fast incremental lane** — [#114: evaluate GPT-5.3-Codex-Spark](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/114) (research backlog).
26. **Benchmark optional model orchestration** — [#72: compare direct Sol/Luna driving with bounded Sol-to-Luna delegation](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/72) (research backlog).
27. **Evaluate Fable before planning** — [#71: measure Fable as an optional planning advisor](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/71) (research backlog).
28. **Research context-pressure policy** — [#77: measure compaction thresholds and subagent effects](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/77) (research backlog).
29. **Evaluate another CLI host** — [#97: research a GitHub Copilot CLI adapter](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/97) (research backlog).
30. **Revisit portable enforcement after host adapters stabilize** — [#58: compare a portable SDLC MCP server with per-host skills](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/58) (research backlog).
31. **Consider a Copilot Studio surface last** — [#96: research a front end only after portable enforcement is justified](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/96) (research backlog).
