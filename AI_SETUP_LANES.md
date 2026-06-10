# AI Setup Lanes

Two recommended AI coding setups for this repo. Each is a complete triad: **planner → driver → reviewer**.

This is **guidance, not a hard rule**. Maintainer override is always allowed.

## Setup A — Codex Premium

| Role | Model |
|------|-------|
| **Planner** | Codex (GPT-5.5) xhigh |
| **Driver** | Codex (GPT-5.5) xhigh |
| **Reviewer** | Claude Code (Opus 4.6) max |

Quality-first lane. GPT-5.5 xhigh drives both the planning brain and the implementation hands; Claude Opus 4.6 max is the cross-model final gate — different lab, different training, different blind spots.

## Setup B — Codex Saver

| Role | Model |
|------|-------|
| **Planner** | Codex (GPT-5.5) xhigh |
| **Driver** | Codex (GPT-5.5) standard |
| **Reviewer** | Claude Code (Opus 4.6) max |

Cost-efficient lane. Keeps GPT-5.5 xhigh as the planning brain — where reasoning matters most — but drops driver effort to standard for routine work. Claude Opus 4.6 max still the final reviewer.

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

Setup B is sufficient for routine work:

- Routine implementation
- Documentation
- Examples
- Tests
- Normal script changes (non-installer)
- Low-risk methodology edits
- Mechanical refactors

## Final Review Policy

**Both lanes end at Claude Opus 4.6 max as the cross-model reviewer.** Codex can't grade its own homework — the reviewer always belongs to a different lab with different blind spots.

**How to run the Claude reviewer from a Codex session:**

```bash
claude -p \
  "Read .reviews/handoff.json and review per the checklist. Output findings + CERTIFIED or NOT CERTIFIED." \
  --model claude-opus-4-6[1m] \
  --output-format text \
  > .reviews/latest-review.md
```

Append `< /dev/null` if running from a non-interactive parent. Use `--model claude-opus-4-6[1m]` explicitly — this pins the reviewer to the wizard's recommended flagship, not whatever alias resolves to. If `claude` CLI is not installed, use `npx @anthropic-ai/claude-code` or the API directly.

## Credit-Spend Warning

Both lanes use GPT-5.5 for the planner + driver — billed against your OpenAI account. The reviewer (Claude Opus 4.6 max) bills against your Anthropic Max subscription for interactive use, or against the Anthropic credit pool for headless `claude -p` use (post-June-15-2026 billing split).

If you're running the reviewer via `claude -p` (headless), that draws from your Anthropic credits:
- Max 5x: $100/mo
- Max 20x: $200/mo
- No rollover

For interactive Claude Code reviews (you open a separate Claude Code session to review), it stays on your Max subscription — no credit drawdown.

## Maintainer Override

**Override at any time.** A blanket setup choice doesn't replace judgment per change. If you're touching CI but the change is a one-line typo, Setup B is fine. If you're touching docs but the section is the installer's safety-critical path, Setup A is the call.

The wizard does not enforce setup lane selection — it documents the recommended default per change shape. Whatever ships is your call.

## See Also

- [`AGENTS.md`](AGENTS.md) — SDLC enforcement rules for this repo
- [claude-sdlc-wizard `AI_SETUP_LANES.md`](https://github.com/BaseInfinity/claude-sdlc-wizard/blob/main/AI_SETUP_LANES.md) — Sibling lanes doc for Claude Code environments (Setup A/B use Claude Opus 4.6 max as primary coder, GPT-5.5 xhigh as reviewer — the inverse of this doc)
