---
name: codex-sdlc-wizard
description: Install or update Codex SDLC enforcement in the current repository. Use when the user wants this wizard set up as Codex hooks/docs, wants adaptive setup, or needs the generated Codex SDLC files repaired.
---

# Codex SDLC Wizard

This skill wraps the bundled `install.sh` and `setup.sh` scripts in this repository.

Use it for:
- installing baseline Codex SDLC enforcement into the current repo
- running adaptive setup that scans the repo and generates docs
- reapplying or repairing the generated Codex hook/config files

Use the bundled scripts like this:

1. If the user wants the simplest install, run the bundled `install.sh` from this skill bundle against the current working repo.
2. If the user wants repo-aware setup or regenerated docs, run the bundled `setup.sh --yes` from this skill bundle against the current working repo.
3. Tell the user exactly which path you chose: `install.sh` for baseline enforcement, `setup.sh` for adaptive setup.
4. After installation, tell the user to start a fresh Codex session so hooks and repo docs are loaded cleanly.

Rules:
- Do not invent a second installer path when the bundled scripts already do the job.
- Prefer `install.sh` unless the user asks for adaptive setup or the repo clearly needs generated docs.
- Preserve existing user files; the installer path is intentionally non-destructive.
- When debugging an install problem, inspect `.codex/config.toml`, `.codex/hooks.json`, and `AGENTS.md` in the target repo first.
