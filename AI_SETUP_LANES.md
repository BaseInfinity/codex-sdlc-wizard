# AI Setup Lanes

Two recommended AI coding setups for this repo. Each is a complete triad: **planner → driver → reviewer**.

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
| **Driver fallback** | GPT-5.4 mini xhigh | If Spark unavailable — also a different bucket |
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

## Final Review Policy

**Both lanes end at GPT-5.5 xhigh as the reviewer.** The review step catches what the driver missed — in Setup A that's self-review at flagship; in Setup B the flagship reviewer catches what the mini driver missed.

## Credit-Spend Warning

Setup A bills everything against your OpenAI account at GPT-5.5 rates. Setup B's driver draws from a **different billing bucket** than GPT-5.5 — that's the cost-saving mechanism:

- **GPT-5.3 Codex Spark** (primary driver): separate bucket because it's a preview model. Max reasoning keeps quality high while the billing stays off the main GPT-5.5 pool.
- **GPT-5.4 mini xhigh** (fallback driver): also a different bucket from GPT-5.5.

The planner and reviewer in Setup B still use GPT-5.5, so the savings come specifically from the driver leg being routed to a cheaper billing pool.

## Maintainer Override

**Override at any time.** A blanket setup choice doesn't replace judgment per change. If you're touching CI but the change is a one-line typo, Setup B is fine. If you're touching docs but the section is the installer's safety-critical path, Setup A is the call.

The wizard does not enforce setup lane selection — it documents the recommended default per change shape. Whatever ships is your call.

## See Also

- [`AGENTS.md`](AGENTS.md) — SDLC enforcement rules for this repo
- [claude-sdlc-wizard `AI_SETUP_LANES.md`](https://github.com/BaseInfinity/claude-sdlc-wizard/blob/main/AI_SETUP_LANES.md) — Sibling lanes doc for Claude Code environments (uses Opus 4.6 max as primary coder + GPT-5.5 xhigh as cross-model reviewer — the Claude-side equivalent)
