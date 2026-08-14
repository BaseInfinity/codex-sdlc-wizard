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
   Freeze one issue, a closed behavior allowlist, one risk lane, and explicit exclusions. Feature creep becomes a separate follow-up issue unless omitting it would make the active change unsafe or nonfunctional.
6. TDD is mandatory: write the failing test first, run it red, implement the minimum fix, then run it green.
   Harness-repair lane: when broken SDLC enforcement or test bootstrap prevents the RED step for its own repair, declare the failing observable and exact file allowlist before editing, make the smallest repair, then write and run the missing regression test immediately after. This exception is only for repairing the harness itself; focused proof, final broad proof, and completion review still apply.
7. Run the narrowest relevant verification first, then the full required suite before shipping.
8. Self-review the exact diff. Check for regressions, scope creep, stale docs, and dead code.
9. For release or publish work, treat version bump, docs, tests, publish, and verification as one SDLC slice.
10. Review is mandatory. The portable contract is review behavior, not a slash-command name.
   Use native Codex review when appropriate: `codex review --uncommitted` before commit, `codex review --base <branch>` for branch or PR-sized diffs, and `codex review --commit <sha>` for a specific commit.
   Use `codex -c 'model_reasoning_effort="high"' review --uncommitted` for an enforced Sol-high gate, especially from `mixed`; apply the same prefix to `--base` or `--commit` reviews.
   Run one broad proof run total on the frozen candidate through the proof-stamping entrypoint. In this repo, use `node .codex/hooks/git-guard.cjs prove --reviewed --check "node scripts/run-proof-suite.cjs"`; do not run the suite directly and then rerun it through the guard.
   Use a prompt-only review when supplying custom proof-aware instructions. A custom prompt must not be combined with `--uncommitted`, `--base`, or `--commit`; those predefined target flags are for reviews without a custom prompt. Include the exact base identity, frozen candidate tree identity, fresh proof command, and result, and say `Do not rerun tests`. Targeted verification is allowed only for a concrete suspected defect; never rerun the broad suite. Missing or stale proof is a blocker to report, not permission to launch another broad suite.
   Reviewer role: inspect the frozen diff and return prioritized code-review findings only; do not edit, implement, run tests, re-plan, or perform follow-up work. The builder owns every correction through the normal SDLC loop.
   `review_model` controls native Codex review model selection but does not set review reasoning independently. `auto_review` is for eligible approval prompts, not code-diff review. Do not require `/autoreview` unless the current Codex host exposes it as a verified feature.
   At each coherent green slice, author-review the exact incremental diff before committing. Once the cumulative candidate is stable, freeze it, run one fresh broad proof, and review the full base-to-candidate diff once. A relevant correction invalidates that completion proof; use narrow delta checks while fixing, then run a fresh final proof.
   Incremental checkpoint: use affected proof, exact-diff author review, and at most one risk-based reviewer before committing a coherent green slice. During the ten-delivery pilot, the completion boundary sends the whole base-to-candidate diff through the bounded Sol High plus Fable High joint gate; outside the pilot, use Fable only when cross-model policy requires it. A finding produces one bounded corrective delta with targeted proof. A third same-plan correction means stop; human approval may authorize a replan with newly scoped work, not silently extend the exhausted plan. Record ten-delivery pilot outcomes in `benchmarks/review-cadence.csv` before making this cadence permanent.
   Severity ladder: P0 stops the line; P1 blocks completion; P2 is a bounded fix now or a follow-up issue; P3 never blocks and is recorded only when worthwhile.
   When two reviewers are required, run `node .codex/hooks/dual-review.cjs --base <ref> --consent-subscription-quota`. Sol High and Fable High assess the same frozen candidate independently. Clean agreement stops immediately; a verdict split receives one verbatim cross-feed round of findings and then produces one conservative joint receipt. Do not add another reconciliation exchange. Allow at most two corrective rounds; if P0/P1 remains, decompose, abandon, or escalate rather than waiving it or continuing an unbounded loop.
   For every corrective finding, check its provenance against the base. If the blocker is candidate-born and outside the allowlist, remove that accretion instead of repairing it.
   If the work is in a product repo, keep that session focused on the product repo. File a direct GitHub issue for proven reusable wizard findings and only switch to live wizard work if the product repo is actually blocked.
11. Present a final summary with what changed, what was verified, and any residual risk.

## Codex-Native Notes

- `skills = explicit workflow layer`
- `hooks = silent event enforcement`
- `repo docs = source of local truth`
- Use Codex's normal planning and review flow; do not assume host-specific task managers or slash commands exist.
- Use Codex's normal image and file-reading capabilities when verifying screenshots or files.
- If repo-local hooks, docs, or checks disagree with this skill, follow the repo contract.
