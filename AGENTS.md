# SDLC Enforcement

## Before Every Task
1. Plan before coding - outline steps, state confidence (HIGH/MEDIUM/LOW)
2. LOW confidence? Research more or ASK USER
3. Reasoning policy - use `gpt-5.6-sol` with `high` reasoning for this repo
4. Always keep this repo on `gpt-5.6-sol` `high`; do not switch wizard-repo work to `mixed`, Terra, Luna, or lower-tier profiles
5. Keep this repo on `maximum` (`gpt-5.6-sol` `high`) because codex-sdlc-wizard is unusually meta and high-blast-radius
6. Default meaningful agentic coding to Sol `high`; escalate only difficult or high-risk slices to `xhigh` when `high` leaves unresolved risk
7. Max is a single-task reasoning escalation; Ultra is a subagent-backed parallel-work escalation. Most tasks do not need Max or Ultra, and neither is a default for this repo.
8. If `GOALS.md` exists, treat it as the active-scope contract and keep `ROADMAP.md` as backlog/history
9. Use RED only when a RED mutation is writable; otherwise choose an honest eval, mechanical assertion, or review gate
10. ALL tests must pass before commit - no exceptions

## Evidence Workflow (MANDATORY)
1. **EVAL it** when agent-facing guidance has an observable scenario.
2. **Plain-assert it** for a mechanical contract.
3. **Review it** for judgment-call prose; cross-model review is the guard.
4. For executable behavior, any observable input/output or side-effect difference makes a RED mutation writable; the meaning exception applies only to prose judged by a reader.
5. Implement-first is allowed only when a named gate blocks the required RED or evidence act itself. A gate refusing implementation because RED is missing is working, not an entry ticket. A cross-model ruling must APPROVE that same act and scope before the edit.
6. Only commit after the selected evidence is green.

## After Implementation
1. Self-review: read back your changes, check for bugs
2. Run full test suite - ALL tests must pass
3. Only then: commit and push

## AI Setup Lanes

This repo ships and uses Sol `high` as the normal root driver, with task-scoped `xhigh` escalation. The Terra-led `mixed` profile is experimental explicit opt-in, and Terra/Luna otherwise stay bounded support options. The root agent normally owns planning; specialist agents and Ultra are optional when the task benefits. See [`AI_SETUP_LANES.md`](AI_SETUP_LANES.md).

## Rules
- Delete legacy code - no backwards compatibility hacks
- Less is more - don't add what wasn't asked for
- Tests ARE code - treat test failures as bugs
- NEVER commit without running tests first
- During setup, environment repair, and auth-heavy workflows, prefer full access
