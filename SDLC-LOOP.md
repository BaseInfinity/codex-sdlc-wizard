# SDLC Loop

Codex does not have a native `/sdlc` command. This file is the honest replacement.

## The Loop

1. Frame the slice
   Restate the task, set a scope guard, state confidence (`HIGH` / `MEDIUM` / `LOW`), and say what will prove the work is done.
2. Pick the reasoning level
   Default to `xhigh` in this repo. Drop lower only when the user explicitly wants a faster or cheaper pass.
3. Red first
   Write the failing test first when the task is code-shaped.
   If the task is setup, auth, or environment repair, define the failing observable first instead of pretending it is unit-testable.
4. Green with the smallest change
   Make the narrowest change that can satisfy the red check.
5. Prove it
   Run the targeted checks, capture the evidence, and make sure the result matches the original success condition.
6. Review the diff
   Read the diff back, note risks, and remove junk before thinking about a commit.
7. Commit only after proof
   Commits happen after tests and proof, not before.
8. Escalate honestly
   If blocked, name the blocker, show the evidence, and propose the next move.

## Testing Shape

- Most checks should be unit tests.
- Some should be integration tests around real boundaries.
- A small number should be E2E checks.
- Use browser E2E where it helps, but do not pretend browser tests replace desktop-only flows such as Word COM.

## Setup And Auth Work

For setup, installs, PATH repair, and auth-heavy workflows:

- Prefer full access.
- Capture before/after evidence.
- Re-run the bootstrap or health check after each fix.
- Treat the health check as the prove-it gate.
