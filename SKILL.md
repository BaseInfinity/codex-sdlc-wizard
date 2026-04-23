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
4. After installation, tell the user to start a fresh Codex session so hooks and repo docs are loaded cleanly. Recommend `codex --full-auto` as the default start mode once the guardrails are installed, and mention plain `codex` as the manual fallback.
   The fresh session should also pick up the repo-scoped `\$sdlc` skill under `.agents/skills`. Repo-scoped skill coverage is still a work in progress; `gdlc` and `rdlc` are planned next.
   For setup/update bootstrap work, recommend the `maximum` profile via `--model-profile maximum` as the safer default. For routine work after bootstrap, point users back to the `mixed` profile via `--model-profile mixed` for the better speed / lower latency / lower token path with `xhigh` review.
   This repo stays on `maximum`; when maintaining `codex-sdlc-wizard` itself, keep the wizard repo on the stability-first path because the work is unusually meta.
   Interactive `setup` should ask for the profile when the user does not pass `--yes` or `--model-profile`, and it should recommend `maximum` as the bootstrap default.
5. For auth-heavy Windows / WAM / MFA flows, say plainly that the live sign-in remains user-owned, while Codex still owns command shape, checks, and the verify/resume path after the user completes sign-in.
6. For auth / license-sensitive repos, encourage a repo-local capability detector such as `doctor`, `check-capability`, or `Test-*Access.ps1` so Codex can start from one-command classification instead of raw provider commands.

Rules:
- Do not invent a second installer path when the bundled scripts already do the job.
- Prefer `install.sh` unless the user asks for adaptive setup or the repo clearly needs generated docs.
- Preserve existing user files; the installer path is intentionally non-destructive.
- When debugging an install problem, inspect `.codex/config.toml`, `.codex/hooks.json`, and `AGENTS.md` in the target repo first.
- Present auth boundaries as workflow ownership, not as refusal language.
- Treat account, license, tenant, and permission state as setup signals when a repo is capability-sensitive.
