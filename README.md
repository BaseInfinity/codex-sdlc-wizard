# Codex SDLC Wizard

An adapter that brings [SDLC Wizard](https://github.com/BaseInfinity/agentic-ai-sdlc-wizard) enforcement to OpenAI's Codex CLI.

## What It Does

- SDLC reminders on every prompt (UserPromptSubmit hook)
- **Hard block** on `git commit` until tests pass (PreToolUse hook)
- **Hard block** on `git push` until self-review (PreToolUse hook)
- TDD guidance via AGENTS.md (soft enforcement — Codex has no Write/Edit tools to hook)
- Session start check for AGENTS.md presence
- Non-destructive installer that merges into existing config

## Quick Start

```bash
# Clone into your project
git clone https://github.com/BaseInfinity/codex-sdlc-wizard.git /tmp/codex-sdlc-wizard

# Install into your project
cd your-project
bash /tmp/codex-sdlc-wizard/install.sh

# Start coding with SDLC enforcement
codex
```

### What install.sh Does

1. Copies `AGENTS.md` (skips if exists)
2. Creates/merges `.codex/config.toml` with `codex_hooks = true`
3. Installs `.codex/hooks.json` (backs up existing)
4. Copies hook scripts to `.codex/hooks/`

### Requirements

- Codex CLI (`npm i -g @openai/codex`)
- `bash` (3.x+ macOS, 4.x+ Linux)
- `jq` (for hook JSON parsing)

## How It Works

| SDLC Goal | Enforcement | Level |
|-----------|-------------|-------|
| TDD workflow | AGENTS.md guidance | Soft (Codex has no file-edit tools to hook) |
| git commit gate | PreToolUse blocks `git commit` | **Hard** (stronger than CC wizard!) |
| git push gate | PreToolUse blocks `git push` | **Hard** (stronger than CC wizard!) |
| SDLC baseline | UserPromptSubmit hook | Context injection every prompt |
| Session init | SessionStart hook | Warns if AGENTS.md missing |

## Upstream

Based on [agentic-ai-sdlc-wizard](https://github.com/BaseInfinity/agentic-ai-sdlc-wizard) — the Claude Code version. Same SDLC philosophy, translated to Codex's Bash-only tool model (~70% parity).

Weekly CI checks for upstream releases and opens sync issues automatically.

## Testing

```bash
bash tests/test-adapter.sh
```

15 behavioral tests covering hook behavior, payload format, config, and install logic.

## License

MIT
