# SDLC Loop

Codex does not have a native `/sdlc` command. This file is the honest replacement.

## The Loop

1. Frame the slice
   Restate one issue, freeze a closed behavior allowlist, one risk lane, and explicit exclusions, state confidence (`HIGH` / `MEDIUM` / `LOW`), and say what will prove the work is done. Feature creep becomes a separate follow-up issue unless omitting it would make the active change unsafe or nonfunctional.
2. Pick the reasoning level
   Default to `high` for meaningful agentic coding. Escalate the difficult slice to `xhigh` for security review, migrations, destructive operations, long-running research, or challenging coding where `high` leaves unresolved risk. Repo-local instructions may define a measured exception.
   Use Max as a single-task escalation only when `xhigh` is not enough. Use Ultra only for subagent-backed parallel work that divides cleanly. Most tasks do not need Max or Ultra.
3. Red first
   Write the failing test first when the task is code-shaped.
   If the task is setup, auth, or environment repair, define the failing observable first instead of pretending it is unit-testable.
   Harness-repair lane: when broken SDLC enforcement or test bootstrap prevents RED for its own repair, declare the failing observable and exact file allowlist, make the smallest repair, then write and run the missing regression test immediately after. This never waives final proof or review.
4. Green with the smallest change
   Make the narrowest change that can satisfy the red check.
5. Prove it
   Run the targeted checks, capture the evidence, and make sure the result matches the original success condition.
6. Review the diff
   Author-review the exact incremental diff, note risks, and remove junk before each coherent green commit.
7. Commit only after proof
   Commit coherent green slices after focused proof. Freeze the cumulative completion candidate and run one fresh broad proof before final review; relevant changes invalidate it and require a fresh final proof.
8. Review to a decision
   Review the full base-to-candidate diff once after it is stable. Severity ladder: P0 stops the line; P1 blocks completion; P2 is a bounded fix now or a follow-up issue; P3 never blocks and is recorded only when worthwhile.
   Run one broad proof run total on the frozen candidate through `node .codex/hooks/git-guard.cjs prove --reviewed`; do not run the suite directly and then rerun it through the guard.
   Use a prompt-only review when supplying custom proof-aware instructions. A custom prompt must not be combined with `--uncommitted`, `--base`, or `--commit`; those predefined target flags are for reviews without a custom prompt. Include the exact base identity, frozen candidate tree identity, proof command, and result and say `Do not rerun tests`. Targeted verification is allowed only for a concrete suspected defect; never rerun the broad suite. Missing or stale proof is a blocker to report, not permission to launch another broad suite.
   Reviewer role: inspect the frozen diff and return prioritized code-review findings only; do not edit, implement, run tests, re-plan, or perform follow-up work. The builder owns every correction through the normal SDLC loop.
   When two reviewers are required, they assess the same frozen candidate independently, exchange compact findings once, and return a joint ledger. Allow at most two corrective rounds. If P0/P1 remains, decompose, abandon, or escalate; never waive it or continue an unbounded review loop.
   Run Fable High only after Sol is clean and only when cross-model policy requires it: `node .codex/hooks/fable-review.cjs --base <ref> --consent-subscription-quota`. Consent acknowledges Claude subscription-quota use; the isolated wrapper refuses API-key and alternate-provider auth and reuses the frozen candidate's proof.
   Check every corrective finding against the base. If the blocker is candidate-born and outside the allowlist, remove that accretion instead of repairing it.
9. Escalate honestly
   If blocked, name the blocker, show the evidence, and propose the next move.

## Task routing gate

Identify the execution lane before giving instructions: CLI, Desktop/computer-use, browser automation, or human-only setup.

Use `Desktop/computer-use` first when a task crosses Microsoft browser sign-in, developer program qualification, account pickers, MFA, tenant consent, Office UI, admin portal state, or other auth-heavy screens that the CLI cannot safely prove.

After naming the lane, provide the handoff prompt and guardrails before any CLI or browser steps. Keep credentials, MFA, tenant consent, subscription creation, license/admin changes, sends, deletes, and policy publishing behind explicit human action.

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

## Codex Desktop handoff

Use Codex Desktop handoff when setup crosses a browser, desktop app, admin portal, screenshot, or auth window that CLI cannot see. Codex Desktop is available on macOS and Windows.

From the repo root:

```bash
codex app .
```

Computer-use work must report back as evidence, not just chat. Prefer a repo-local `.reviews/desktop-computer-use-report.md` or equivalent artifact with findings, blockers, screenshots by path, and the next CLI action.

Human-in-the-loop boundary:

- Codex may navigate, read screens, click non-destructive controls, and explain state.
- The user handles credentials, MFA, tenant consent, sends, deletes, license/admin changes, and policy publishing.
- Return to CLI for code changes, tests, commits, and push.

## Microsoft 365 auth lane

For Microsoft 365 setup, prefer Graph PowerShell first when `Get-MgContext` works. Browser or Desktop sign-in success is not enough by itself; verify the resulting script context before treating the lane as proven.

Fallback proof rules:

- Require tenant id plus expected work account before accepting a raw OAuth REST or device-code proof.
- Treat personal Microsoft account success as invalid for work-tenant validation.
- Keep fallback proofs read-only unless the user approves a draft, send, delete, license/admin, or policy action for that exact run.
- Record the proven lane, current status, artifacts, and next CLI action in `.reviews/` so the next agent does not repeat auth discovery from chat memory.
