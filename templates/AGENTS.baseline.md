# SDLC Enforcement

Read `TESTING.md` and `ARCHITECTURE.md` when present and relevant. If `GOALS.md` exists, treat it as the active-scope contract and keep `ROADMAP.md` as backlog and history.

## Before Every Task

1. Plan before coding. State the task, scope, confidence, and verification gate.
2. If confidence is not high, research more before editing and ask only when material uncertainty remains.
3. Write a failing test first for code-shaped changes, then implement the minimum fix.
4. Run focused checks, the broader relevant suite, and a self-review before commit.
5. Never claim completion without fresh proof.

## Model Policy

- Selected profile: `{{MODEL_PROFILE}}`
- Baseline reasoning: `{{REASONING_BASELINE}}`
- `maximum`: `gpt-5.6-sol` at `high`; this is the default and normal standing root driver. The profile name selects the maximum model tier, not Max reasoning.
- `mixed`: experimental explicit opt-in using `gpt-5.6-terra` at `medium` with `gpt-5.6-sol` review; use an explicit `model_reasoning_effort="high"` review override because `review_model` does not set effort.
- Terra and Luna are bounded support options, not normal SDLC drivers.
- Escalate to `xhigh` for security review, migrations, destructive operations, long-running research, or difficult coding when `high` leaves unresolved risk.
- Max is a single-task reasoning escalation. Ultra is a subagent-backed parallel-work escalation. Most tasks do not need either.
- The root agent normally owns planning. Add explorer, reviewer, or planner agents only when specialization or parallelism improves the work.

## TDD Workflow

1. Write the failing test or failing observable.
2. Run it and confirm RED.
3. Implement the smallest coherent change.
4. Run the focused check and confirm GREEN.
5. Run the full relevant proof and review the exact diff.

## Git Gates

- Do not commit without passing proof.
- Do not push without self-review.
- Preserve unrelated user changes in a dirty worktree.
- Never use destructive git commands unless the user explicitly requests them.

## Rules

- Keep changes scoped to the request.
- Delete dead code instead of adding compatibility hacks.
- Treat tests as production code.
- Prefer full access during setup, environment repair, and auth-heavy workflows.
