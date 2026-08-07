# Codex SDLC Wizard Roadmap

## How to use this roadmap

- GitHub issues are the source of truth for scope, acceptance criteria, milestones, and status.
- The numbered order below is the project priority. The first open item is the next item to work unless `GOALS.md` names a narrower active objective.
- `GOALS.md`, when present, is the active-scope contract. `ROADMAP.md` is the ordered backlog, not a second implementation plan.
- When priorities change, reorder links here and update the corresponding GitHub milestones or issue bodies rather than copying their details into this file.
- Create or deduplicate a GitHub issue before adding an actionable priority here.
- Completed implementation history belongs in pull requests and GitHub releases, not in an ever-growing roadmap narrative.

## Current State

- Current GitHub release: [`v0.7.35`](https://github.com/BaseInfinity/codex-sdlc-wizard/releases/tag/v0.7.35)
- Current npm release: [`codex-sdlc-wizard@0.7.35`](https://www.npmjs.com/package/codex-sdlc-wizard/v/0.7.35)
- Next release milestone: [`0.7.36 — Plugin submission candidate`](https://github.com/BaseInfinity/codex-sdlc-wizard/milestone/1)

## Priority queue

1. **Accept the real Windows candidate** — [#79: Run the plugin submission candidate on real Windows Codex Desktop and CLI](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/79).
2. **Resolve the remaining Windows cleanup finding** — [#92: Investigate flaky access-denied proof cleanup on Windows](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/92).
3. **Stop redundant reviewer test reruns** — [#73: Use proof-aware prompt-only native Codex review](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/73).
4. **Timebox one cumulative upstream audit** — [#65: Audit upstream v1.74.0 through v1.90.0](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/65) together with [#81: Extend the audit through v1.91.0](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/81).
5. **Reconcile the older handoff prototype** — [#67: Prototype handoff for hook merge, install consistency, cross-vendor review, and release drift](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/67).
6. **Codify known-good upgrade stability** — [#84: Adopt a preserve-known-good stability contract](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/84).
7. **Publish and verify `0.7.36` only after Windows acceptance** — [#88: Publish and verify codex-sdlc-wizard 0.7.36](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/88).
8. **Submit only the Windows-verified public release** — [#66: Submit Codex SDLC Wizard to the universal Plugins Directory](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/66).
9. **Land dual-review hardening after the submission candidate** — [#64: Use `claude --print` as the cross-model reviewer](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/64) (`0.7.37`).
10. **Prototype the optional orchestration lane** — [#72: Benchmark Sol High orchestration with Luna Max implementation subagents](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/72) (`0.8.0`).
11. **Add one read-only health entrypoint** — [#82: Add a Codex-native doctor flow](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/82).
12. **Measure maintainer reasoning effort** — [#86: Benchmark Sol high against the former xhigh maintainer exception](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/86).
13. **Evaluate Fable before planning** — [#71: Evaluate Fable as an optional planning advisor](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/71).
14. **Research context-pressure policy** — [#77: Research compaction thresholds and Luna subagent effects](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/77).
15. **Revisit convergence only after the host adapters stabilize** — [#58: Evaluate portable SDLC MCP versus per-host skills](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/58).
