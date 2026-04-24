# SDLC Enforcement

## Before Every Task
1. Plan before coding - outline steps, state confidence (HIGH/MEDIUM/LOW)
2. LOW confidence? Research more or ASK USER
3. Reasoning policy - use `gpt-5.5` with `xhigh` reasoning for this repo
4. Always keep this repo on `gpt-5.5` `xhigh`; do not switch wizard-repo work to `mixed`, mini-only, or lower-reasoning profiles
5. Keep this repo on `maximum` (`gpt-5.5` `xhigh` throughout) because codex-sdlc-wizard is unusually meta and high-blast-radius
6. Write failing test FIRST (TDD RED), then implement (TDD GREEN)
7. ALL tests must pass before commit - no exceptions

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

## Rules
- Delete legacy code - no backwards compatibility hacks
- Less is more - don't add what wasn't asked for
- Tests ARE code - treat test failures as bugs
- NEVER commit without running tests first
- During setup, environment repair, and auth-heavy workflows, prefer full access
