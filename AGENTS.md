# SDLC Enforcement

## Before Every Task
1. Plan before coding — outline steps, state confidence (HIGH/MEDIUM/LOW)
2. If confidence is below 95%, research more first. If it still stays below 95%, escalate review to xhigh or switch to the maximum model profile for abstract, complex, or high-blast-radius work.
3. Write failing test FIRST (TDD RED), then implement (TDD GREEN)
4. ALL tests must pass before commit — no exceptions

## TDD Workflow (MANDATORY)
1. Write the test file FIRST — the test MUST FAIL initially
2. Run the test — confirm it fails (RED)
3. Write the minimum implementation to make the test pass
4. Run the test — confirm it passes (GREEN)
5. Only then: commit

## After Implementation
1. Self-review: read back your changes, check for bugs
2. Run full test suite — ALL tests must pass
3. Only then: commit and push

## Rules
- Delete legacy code — no backwards compatibility hacks
- Less is more — don't add what wasn't asked for
- Tests ARE code — treat test failures as bugs
- NEVER commit without running tests first

## Honest Codex Shape
- `skills = explicit workflow layer`
- `hooks = silent event enforcement`
- `repo docs = source of local truth`

## Repo Focus
- Keep slices small enough that confidence stays high in practice
- Always state confidence on meaningful work
- File a direct GitHub issue for proven reusable wizard findings
- Keep the active session focused on the product repo unless it is actually blocked

## Model Profiles
- `mixed`: `gpt-5.4-mini` main pass plus `gpt-5.4` `xhigh` review for better speed and lower token usage
- `maximum`: `gpt-5.4` `xhigh` throughout for maximum stability and depth
