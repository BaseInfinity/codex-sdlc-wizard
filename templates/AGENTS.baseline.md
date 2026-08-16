# SDLC Enforcement

Read `TESTING.md` and `ARCHITECTURE.md` when present and relevant. If `GOALS.md` exists, treat it as the active-scope contract and keep `ROADMAP.md` as backlog and history.

## Before Every Task

1. Plan before coding. State the task, scope, confidence, and verification gate.
   Freeze one issue, a closed behavior allowlist, one risk lane, and explicit exclusions. Feature creep becomes a separate follow-up issue unless omission would make the active change unsafe or nonfunctional.
2. If confidence is not high, research more before editing and ask only when material uncertainty remains.
3. Write a failing test first for code-shaped changes, then implement the minimum fix.
   Harness-repair lane: if broken enforcement prevents RED for its own repair, declare the failing observable and exact file allowlist, make the smallest repair, then write and run the missing regression test immediately after. Final proof and review remain mandatory.
4. Run focused checks, the broader relevant suite, and a self-review before commit.
5. Never claim completion without fresh proof.
6. Author-review and commit coherent green slices. Freeze the cumulative candidate for one fresh broad proof and completion review.
   Incremental checkpoint: use affected proof, exact-diff author review, and at most one risk-based reviewer before a coherent green commit. During the ten-delivery pilot, the completion boundary sends the whole base-to-candidate diff through the bounded Sol High plus repo-selected cross-model joint gate; outside the pilot, invoke the cross-model reviewer only when policy requires it. A blocker becomes one bounded corrective delta with targeted proof. A third same-plan correction means stop; human approval may authorize a replan with newly scoped work, not silently extend the exhausted plan. Record ten-delivery pilot outcomes in `benchmarks/review-cadence.csv` before making the cadence permanent.
7. Severity ladder: P0 stops the line; P1 blocks completion; P2 is a bounded fix or follow-up issue; P3 never blocks. When two reviewers are required, they exchange compact findings once. Allow at most two corrective rounds; unresolved P0/P1 requires decomposition, abandonment, or escalation.
   Run one broad proof run total on the frozen candidate through `node .codex/hooks/git-guard.cjs prove --reviewed`; do not run the suite directly and then rerun it through the guard.
   Use a prompt-only review when supplying custom proof-aware instructions. A custom prompt must not be combined with `--uncommitted`, `--base`, or `--commit`; those predefined target flags are for reviews without a custom prompt. Include the exact base identity, frozen candidate tree identity, proof command, and result and say `Do not rerun tests`. Targeted verification is allowed only for a concrete suspected defect; never rerun the broad suite. Stale proof is a blocker to report, not permission to launch another broad suite.
   Reviewer role: inspect the frozen diff and return prioritized code-review findings only; do not edit, implement, run tests, re-plan, or perform follow-up work. The builder owns every correction through the normal SDLC loop.
   When both reviewers are required, run `node .codex/hooks/dual-review.cjs --base <ref> --consent-subscription-quota`. Sol High and the repo-selected `fable-high` or `opus-4.8-xhigh` reviewer inspect the same frozen candidate independently; clean agreement stops immediately, while a split gets one verbatim cross-feed round before one conservative joint receipt. Only Fable quota/model unavailability permits one honest Opus fallback; other failures do not. The receipt records the requested and actual reviewer identity. Consent acknowledges Claude subscription-quota use.
   After certification, integrate with `node .codex/hooks/dual-review.cjs deliver github --message <text> --branch <name> --base <name> --title <text> --body <text>`. It honors configured Git hooks, commits and publishes only the certified candidate, and requires at least one completed PR check before atomically advancing an unchanged base to that exact commit. Use `--allow-no-checks` only when the repository intentionally has no GitHub checks. Use `deliver direct` only for an explicit non-GitHub integration path.
   If a blocker is candidate-born and outside the allowlist, remove that accretion instead of repairing it.

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
- For a commit or push from a linked worktree, use a standalone `git -C <absolute-worktree> commit ...` or `git -C <absolute-worktree> push ...`; never rely only on the execution tool's `workdir`, because some Codex surfaces omit it from PreToolUse payloads.
- Preserve unrelated user changes in a dirty worktree.
- Never use destructive git commands unless the user explicitly requests them.

## Rules

- Keep changes scoped to the request.
- Delete dead code instead of adding compatibility hacks.
- Treat tests as production code.
- Prefer full access during setup, environment repair, and auth-heavy workflows.
