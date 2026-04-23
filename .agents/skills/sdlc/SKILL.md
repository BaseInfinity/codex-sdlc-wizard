---
name: sdlc
description: Full software delivery lifecycle for implementation, bug fixes, refactors, testing, release, and publish work in this repo. Use when changing code or docs that should follow the repo's SDLC contract.
argument-hint: [task description]
effort: high
---

# SDLC Skill

## Task

$ARGUMENTS

Use this skill for implementation, bug-fix, refactor, testing, release, publish, or deploy work.

1. Read `AGENTS.md` first and treat it as the process contract.
2. Read `TESTING.md` and `ARCHITECTURE.md` when they exist and are relevant to the change.
3. Plan before coding. State confidence as `HIGH`, `MEDIUM`, or `LOW`.
4. If confidence is below 95% for the next slice, research more before coding. Ask the user only if the uncertainty stays material.
   Keep slices small enough that confidence stays high in practice. If confidence is not high, say why plainly and tighten the slice.
5. TDD is mandatory: write the failing test first, run it red, implement the minimum fix, then run it green.
6. Run the narrowest relevant verification first, then the full required suite before shipping.
7. Self-review the exact diff. Check for regressions, scope creep, stale docs, and dead code.
8. For release or publish work, treat version bump, docs, tests, publish, and verification as one SDLC slice.
9. Review is mandatory. The portable contract is review behavior, not a slash-command name.
   If the work is in a product repo, keep that session focused on the product repo. File a direct GitHub issue for proven reusable wizard findings and only switch to live wizard work if the product repo is actually blocked.
10. Present a final summary with what changed, what was verified, and any residual risk.

## Codex-Native Notes

- `skills = explicit workflow layer`
- `hooks = silent event enforcement`
- `repo docs = source of local truth`
- Use Codex's normal planning and review flow; do not assume host-specific task managers or slash commands exist.
- Use Codex's normal image and file-reading capabilities when verifying screenshots or files.
- If repo-local hooks, docs, or checks disagree with this skill, follow the repo contract.
