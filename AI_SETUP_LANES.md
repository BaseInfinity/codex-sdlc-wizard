# AI Setup Lanes

Three recommended AI coding setups for this repo. Setups A and B are complete triads: **planner → driver → reviewer**. Setup C is a lightweight driver-only lane for operational grunt work.

This is **guidance, not a hard rule**. Maintainer override is always allowed.

## Setup A — Codex Premium

| Role | Model |
|------|-------|
| **Planner** | Codex (GPT-5.5) xhigh |
| **Driver** | Codex (GPT-5.5) xhigh |
| **Reviewer** | Codex (GPT-5.5) xhigh |

Quality-first lane. GPT-5.5 xhigh all the way through — planning, implementation, and review all stay at the flagship level. No model switching, no billing-pool surprises. One model, one effort level, maximum quality.

## Setup B — Codex Saver

| Role | Model | Notes |
|------|-------|-------|
| **Planner** | Codex (GPT-5.5) xhigh | |
| **Driver** | GPT-5.3 Codex Spark (max reasoning) | Primary — different billing bucket (preview) |
| **Driver fallback** | GPT-5.4 mini xhigh | If Spark unavailable — same billing pool as GPT-5.5 but cheaper per token |
| **Reviewer** | Codex (GPT-5.5) xhigh | |

Cost-efficient lane. Keeps GPT-5.5 xhigh as both the planning brain and the final reviewer — where reasoning and judgment matter most. Moves the driver to **GPT-5.3 Codex Spark** (max reasoning), which draws from a separate billing bucket because it's currently a preview model. If Spark isn't available, fall back to **GPT-5.4 mini xhigh** (also a different bucket). The cheaper driver handles routine coding while the flagship reviewer catches what it missed.

## When to Use Setup A

Reach for Premium when the change can damage a consumer repo or has high blast radius:

- Architecture or methodology changes
- Tagged release prep
- Installer behavior (`install.sh`, `setup.sh`, `bin/`)
- Destructive file operations
- Package publishing
- Generated repo modifications (template changes)
- CI / release automation
- Security-sensitive behavior
- Anything that could damage a consumer repo

## When to Use Setup B

Setup B is sufficient for routine work where the mini driver can ship with a strong reviewer:

- Routine implementation
- Documentation
- Examples
- Tests
- Normal script changes (non-installer)
- Low-risk methodology edits
- Mechanical refactors

## Setup C — Codex Lite

| Role | Model | Notes |
|------|-------|-------|
| **Planner** | You (the user) | Task is pre-planned, no model reasoning needed |
| **Driver** | GPT-5.4 mini standard | Cheapest available in the Codex ecosystem |
| **Driver fallback** | GPT-5.4 standard | If mini can't handle the task |
| **Reviewer** | None | Blast radius too low for review overhead |

The "just do the thing" lane. No SDLC enforcement, no cross-model review, no planning phase. You already know what to do — you just need a fast, cheap pair of hands.

## When to Use Setup C

Setup C is for work where SDLC discipline overhead exceeds the value:

- Run a script with basic intelligence
- Deploy to staging or prod
- Config updates, env var changes
- File moves, renames, bulk operations
- Repo maintenance (dependency bumps, lockfile refreshes)
- Simple administrative tasks
- Anything where blast radius is low and you need speed, not depth

**Escalation rule:** if the task turns out harder than expected, escalate to Setup B or A. Don't force-fit mini on a complex problem.

## Final Review Policy

**Setups A and B end at GPT-5.5 xhigh as the reviewer.** The review step catches what the driver missed — in Setup A that's self-review at flagship; in Setup B the flagship reviewer catches what the mini driver missed.

**Setup C has no reviewer** — the blast radius doesn't justify it. If you're unsure whether a task is truly Lite, it probably isn't. Escalate.

## Credit-Spend Warning

Setup A bills everything against your OpenAI account at GPT-5.5 rates. Setup B's driver draws from a **different billing bucket** than GPT-5.5 — that's the cost-saving mechanism:

- **GPT-5.3 Codex Spark** (primary driver): separate bucket because it's a preview model. Max reasoning keeps quality high while the billing stays off the main GPT-5.5 pool.
- **GPT-5.4 mini xhigh** (fallback driver): same billing pool as GPT-5.5 but cheaper per token.

The planner and reviewer in Setup B still use GPT-5.5, so the savings come specifically from the driver leg being routed to a cheaper billing pool.

## Maintainer Override

**Override at any time.** A blanket setup choice doesn't replace judgment per change. If you're touching CI but the change is a one-line typo, Setup B is fine. If you're touching docs but the section is the installer's safety-critical path, Setup A is the call.

The wizard does not enforce setup lane selection — it documents the recommended default per change shape. Whatever ships is your call.

## See Also

- [`AGENTS.md`](AGENTS.md) — SDLC enforcement rules for this repo
- [claude-sdlc-wizard `AI_SETUP_LANES.md`](https://github.com/BaseInfinity/claude-sdlc-wizard/blob/main/AI_SETUP_LANES.md) — Sibling lanes doc for Claude Code environments (uses Opus 4.6 max as primary coder + GPT-5.5 xhigh as cross-model reviewer — the Claude-side equivalent)
