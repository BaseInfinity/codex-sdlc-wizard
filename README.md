# Codex SDLC Wizard (Experimental)

An adapter that brings [SDLC Wizard](https://github.com/BaseInfinity/agentic-ai-sdlc-wizard) enforcement to OpenAI's Codex CLI.

## Status: Plan Only — Implementation Needed

The `CODEX_ADAPTER_PLAN.md` has been certified through cross-model review (scored 9/10). It contains full specs for every file, hook script, test, and install flow. **No code has been written yet.**

If you want to help convert this plan into working code — PRs welcome! The plan is detailed enough to implement directly (TDD: tests first, then code).

## What This Will Do

- SDLC reminders on every prompt (UserPromptSubmit hook)
- **Hard block** on `git commit` until tests pass (PreToolUse hook)
- **Hard block** on `git push` until self-review (PreToolUse hook)
- TDD guidance via AGENTS.md (soft enforcement — Codex has no Write/Edit tools to hook)
- Non-destructive installer that merges into existing config

## Upstream

Based on [agentic-ai-sdlc-wizard](https://github.com/BaseInfinity/agentic-ai-sdlc-wizard) — the Claude Code version. Same SDLC philosophy, translated to Codex's Bash-only tool model (~70% parity).

## Getting Started (for contributors)

1. Read `CODEX_ADAPTER_PLAN.md` — it has everything
2. Start with the test plan (tests 1-15)
3. Implement TDD: write `tests/test-adapter.sh` first, then the hook scripts
4. Open a PR

## License

MIT
