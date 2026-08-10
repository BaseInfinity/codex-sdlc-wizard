---
name: sdlc
description: Full SDLC workflow for Codex. Use when implementing features, fixing bugs, refactoring, testing, or reviewing work that needs planning, TDD, proof, and self-review.
---

# SDLC

## Purpose

This is the Codex-native SDLC workflow skill. It is the honest equivalent of a missing `/sdlc` command.

Use it for:

- features
- bug fixes
- refactors
- testing work
- risky reviews
- shipping slices that need real proof

## Mandatory first action

Before doing anything else, read the repo-local contract when present:

- `AGENTS.md`
- `README.md`
- `ROADMAP.md`
- `SDLC-LOOP.md`
- `START-SDLC.md`
- `PROVE-IT.md`
- `TESTING.md`
- `ARCHITECTURE.md`

Repo-local guidance wins over generic skill guidance.

## Full workflow

### 1. Planning

For meaningful work, make these visible before implementation:

- task
- scope
- confidence
- verification plan
- one issue with a closed behavior allowlist, one risk lane, and explicit exclusions

Feature creep becomes a separate follow-up issue unless omitting it would make the active change unsafe or nonfunctional.

Check:

- what docs or specs matter
- what patterns already exist
- blast radius
- whether a new pattern is actually needed
- whether the test approach matches `TESTING.md`
- Task routing gate: before giving execution steps, identify the execution lane as CLI, Desktop/computer-use, browser automation, or human-only setup. If Microsoft browser sign-in, developer program qualification, account pickers, MFA, tenant consent, Office UI, admin portal state, or other auth-heavy screens are involved, say `Desktop/computer-use` first, then provide handoff guardrails before CLI/browser steps.

Before implementation, do a docs update for the relevant feature area when the code change affects behavior, assumptions, or operator workflow.

### 2. TDD

Prefer:

1. red
2. green
3. prove-it

If strict test-first is not realistic for the very first primitive or baseline slice, say so explicitly and get back to TDD as soon as the baseline exists.

Harness-repair lane: when broken SDLC enforcement or test bootstrap prevents the RED step for its own repair, declare the failing observable and exact file allowlist before editing, make the smallest repair, then write and run the missing regression test immediately after. This is not a general test waiver; focused proof, final broad proof, and completion review still apply.

### 3. Prove-it

Before commit or handoff, run the broader checks that matter for the slice.

In this ecosystem, `prove-it` often matters more than unit success because:

- hooks can block risky git actions
- mocks can lie
- Graph, COM, browser, and tenant behavior often need integration proof

### 4. Self-review

Read back what changed and check for:

- scope creep
- dead code
- fake confidence from mocks
- missing docs
- missing verification

Use native Codex review for a second pass when the slice warrants it:

- `codex review --uncommitted` before commit
- `codex review --base <branch>` for branch or PR-sized diffs
- `codex review --commit <sha>` for a specific commit
- `codex -c 'model_reasoning_effort="high"' review --uncommitted` when enforcing a Sol-high gate, especially from the experimental mixed profile

`review_model` controls native Codex review model selection but does not set review reasoning independently. Mixed mode must use the explicit `high` command override above; apply the same prefix to `--base` or `--commit` reviews. This is a CLI review path, not a slash-command contract.

Pass the fresh proof command and result in the custom review prompt and say `Do not rerun tests`; the reviewer inspects the diff and evidence. Missing or stale proof is a blocker to report, not permission to launch another broad suite.

`auto_review` is for eligible approval prompts, not code-diff review. Do not require `/autoreview` unless the current Codex host exposes it as a verified feature.

At each coherent green slice, author-review the exact incremental diff before committing. Once the cumulative candidate is stable, freeze it, run one fresh broad proof, and review the full base-to-candidate diff once. A relevant correction invalidates that completion proof; use narrow delta checks while fixing, then run a fresh final proof.

Severity ladder: P0 stops the line; P1 blocks completion; P2 is a bounded fix now or a follow-up issue; P3 never blocks and is recorded only when worthwhile.

When two reviewers are required, they assess the same frozen candidate independently, exchange compact findings once, and return a joint ledger. Allow at most two corrective rounds. If P0/P1 remains, decompose, abandon, or escalate; never waive it or continue an unbounded review loop.

For every corrective finding, check its provenance against the base. If the blocker is candidate-born and outside the allowlist, remove that accretion instead of repairing it.

### 5. CI and Merge Guard

Never use auto-merge in this repo.

`NEVER AUTO-MERGE`

Read CI logs, handle valid review feedback, and merge explicitly only after the proof matches the diff.

### 6. Final summary

Before handoff, make these visible:

- what changed
- what was verified
- what is still risky or unverified

### 7. Capture Learnings

If the session uncovered reusable lessons, capture learnings in the right local doc:

- `TESTING.md` for testing lessons
- feature docs for feature-specific behavior
- `ARCHITECTURE.md` for architecture decisions
- `README.md` or repo-local workflow docs when the user-facing setup story changed

## Confidence policy

- default: `high`
- keep `gpt-5.6-sol` as the normal standing root driver for meaningful SDLC work; Terra/Luna are bounded support options, not automatic downgrades
- escalate security review, migrations, destructive operations, long-running research, and difficult coding to `xhigh` when `high` leaves unresolved risk
- repo-local guidance may define a measured `xhigh` exception for unusually high-blast-radius maintenance
- Max is a single-task escalation; Ultra is a subagent-backed parallel-work escalation, and neither is a default profile
- use lower effort only when the task is straightforward and the speed/cost tradeoff is intentional

## Hooks vs skill

- hooks are silent, event-driven enforcement
- this skill is the user-facing workflow layer
- do not pretend Codex has a native `/sdlc` command if it does not

## Naming

- Canonical entrypoint: `$sdlc`
- Early adapter-specific SDLC skill names should be removed by setup/update so users do not see two SDLC workflows for the same contract.

## Quality bar

- keep changes small and coherent
- prefer boring correctness over cleverness
- do not commit what you did not prove
