# SDLC Enforcement

## Before Every Task
1. Plan before coding - outline steps, state confidence (HIGH/MEDIUM/LOW)
2. LOW confidence? Research more or ASK USER
3. Reasoning policy - use `gpt-5.6-sol` with `xhigh` reasoning for this repo
4. Always keep this repo on `gpt-5.6-sol` `xhigh`; do not switch wizard-repo work to `mixed`, Terra, Luna, or lower-reasoning profiles
5. Keep this repo on `maximum` (`gpt-5.6-sol` `xhigh` throughout) because codex-sdlc-wizard is unusually meta and high-blast-radius
6. Consumer repos default meaningful agentic coding to Sol `high`; this repo keeps its measured Sol `xhigh` maintainer exception until representative slices show `high` preserves quality
7. Max is a single-task reasoning escalation; Ultra is a subagent-backed parallel-work escalation. Most tasks do not need Max or Ultra, and neither is a default for this repo.
8. If `GOALS.md` exists, treat it as the active-scope contract and keep `ROADMAP.md` as backlog/history
9. Write failing test FIRST (TDD RED), then implement (TDD GREEN)
10. ALL tests must pass before commit - no exceptions

## TDD Workflow (MANDATORY)
1. Write the test file FIRST - the test MUST FAIL initially
2. Run the test - confirm it fails (RED)
3. Write the minimum implementation to make the test pass
4. Run the test - confirm it passes (GREEN)
5. Only then: commit

## After Implementation
1. Self-review: read back your changes, check for bugs
2. Run full test suite - ALL tests must pass
3. Only then: commit and push

## AI Setup Lanes

This repo ships Sol `high` as the normal consumer root driver, with task-scoped `xhigh` escalation. The Terra-led `mixed` profile is experimental explicit opt-in, and Terra/Luna otherwise stay bounded support options. The root agent normally owns planning; specialist agents and Ultra are optional when the task benefits. This repo itself remains the documented Sol `xhigh` maintainer exception. See [`AI_SETUP_LANES.md`](AI_SETUP_LANES.md).

## Rules
- Delete legacy code - no backwards compatibility hacks
- Less is more - don't add what wasn't asked for
- Tests ARE code - treat test failures as bugs
- NEVER commit without running tests first
- During setup, environment repair, and auth-heavy workflows, prefer full access
