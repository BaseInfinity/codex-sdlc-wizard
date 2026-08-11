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
- Next release milestone: [`0.7.36 — Windows-stable plugin candidate`](https://github.com/BaseInfinity/codex-sdlc-wizard/milestone/1)

## Priority queue

1. **Restore the Windows automation baseline** — [#98: Return the Git Bash npm/handoff suite to 25/25 passing](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/98).
2. **Enforce the chosen Sol High policy everywhere** — [#86: Remove autonomous `xhigh` escalation](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/86).
3. **Make native review proof-aware across every shipped layer** — [#73: Avoid redundant reviewer suite reruns](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/73).
4. **Resolve nondeterministic Windows proof cleanup** — [#92: Investigate the access-denied proof-stamp race](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/92).
5. **Keep Windows review evidence honest** — [#93: Detect WindowsApps PowerShell before trusting Codex review validation](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/93).
6. **Codify known-good upgrade stability** — [#84: Adopt a preserve-known-good stability contract](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/84).
7. **Publish and verify `0.7.36` after the automated release gates pass** — [#88: Publish and verify codex-sdlc-wizard 0.7.36](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/88).
8. **Validate the published release on real Windows** — [#79: Run the released plugin in Codex Desktop and CLI](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/79).
9. **Land bounded dual-review enforcement** — [#64: Use `claude --print` as the cross-model reviewer](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/64) (`0.7.37`).
10. **Audit instruction ownership and freshness** — [#95: Audit `AGENTS.md` against current Codex guidance](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/95) (`0.7.37`).
11. **Make the GitHub lifecycle explicit and enforceable** — [#100: Teach issue-to-PR-to-milestone delivery](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/100) (`0.7.37`).
12. **Rename the public harness without breaking npm compatibility** — [#101: Rename wizard to harness using the proven migration checklist](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/101) (`0.7.37`).
13. **Submit only the hardened, Windows-verified public release** — [#66: Submit Codex SDLC Wizard to the universal Plugins Directory](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/66).
14. **Prototype the optional orchestration lane** — [#72: Benchmark Sol High orchestration with bounded Luna implementation work](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/72) (`0.8.0`).
15. **Add one read-only health entrypoint** — [#82: Add a Codex-native doctor flow](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/82).
16. **Timebox one cumulative upstream audit** — [#65: Audit upstream v1.74.0 through v1.91.0](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/65).
17. **Detect public-release drift deterministically** — [#99: Add release-drift detection and issue reconciliation](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/99).
18. **Evaluate Fable before planning** — [#71: Evaluate Fable as an optional planning advisor](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/71).
19. **Research context-pressure policy** — [#77: Research compaction thresholds and Luna subagent effects](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/77).
20. **Research a Copilot CLI host adapter** — [#97: Evaluate GitHub Copilot CLI support](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/97).
21. **Revisit portable enforcement after host adapters stabilize** — [#58: Evaluate portable SDLC MCP versus per-host skills](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/58).
22. **Consider a Copilot Studio surface only after portable enforcement exists** — [#96: Evaluate a Copilot Studio front end](https://github.com/BaseInfinity/codex-sdlc-wizard/issues/96).
