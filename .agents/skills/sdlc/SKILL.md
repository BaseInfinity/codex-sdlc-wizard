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
4. Task routing gate: before giving execution steps, identify the execution lane as CLI, Desktop/computer-use, browser automation, or human-only setup. If Microsoft browser sign-in, developer program qualification, account pickers, MFA, tenant consent, Office UI, admin portal state, or other auth-heavy screens are involved, say `Desktop/computer-use` first, then provide handoff guardrails before CLI/browser steps.
5. If confidence is below 95% for the next slice, research more before coding. Ask the user only if the uncertainty stays material.
   Keep slices small enough that confidence stays high in practice. If confidence is not high, say why plainly and tighten the slice.
6. TDD is mandatory: write the failing test first, run it red, implement the minimum fix, then run it green.
7. Run the narrowest relevant verification first, then the full required suite before shipping.
8. Self-review the exact diff. Check for regressions, scope creep, stale docs, and dead code.
9. For release or publish work, treat version bump, docs, tests, publish, and verification as one SDLC slice.
10. Review is mandatory. The portable contract is review behavior, not a slash-command name.
   Use native Codex review when appropriate: `codex review --uncommitted` before commit, `codex review --base <branch>` for branch or PR-sized diffs, and `codex review --commit <sha>` for a specific commit.
   `review_model` controls native Codex review model selection; `auto_review` is for eligible approval prompts, not code-diff review. Do not require `/autoreview` unless the current Codex host exposes it as a verified feature.
   If the work is in a product repo, keep that session focused on the product repo. File a direct GitHub issue for proven reusable wizard findings and only switch to live wizard work if the product repo is actually blocked.
11. Present a final summary with what changed, what was verified, and any residual risk.

## Codex-Native Notes

- `skills = explicit workflow layer`
- `hooks = silent event enforcement`
- `repo docs = source of local truth`
- Use Codex's normal planning and review flow; do not assume host-specific task managers or slash commands exist.
- Use Codex's normal image and file-reading capabilities when verifying screenshots or files.
- If repo-local hooks, docs, or checks disagree with this skill, follow the repo contract.
