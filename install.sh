#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "Installing SDLC Wizard for Codex CLI..."

# AGENTS.md — skip if exists
if [ ! -f "AGENTS.md" ]; then
  cp "$SCRIPT_DIR/AGENTS.md" .
  echo "Created AGENTS.md"
else
  echo "AGENTS.md already exists — skipping (review manually)"
fi

install_repo_skill() {
  local name="$1"
  local source="$SCRIPT_DIR/.agents/skills/$name/SKILL.md"
  local target=".agents/skills/$name/SKILL.md"

  if [ ! -f "$source" ]; then
    echo "Skill source missing for $name — skipping"
    return
  fi

  mkdir -p "$(dirname "$target")"

  if [ -f "$target" ]; then
    echo "$target already exists — skipping (review manually)"
  else
    cp "$source" "$target"
    echo "Installed $target"
  fi
}

mkdir -p .codex/hooks

# config.toml — ensure codex_hooks = true, TOML-safe
if [ -f ".codex/config.toml" ]; then
  if grep -v '^[[:space:]]*#' .codex/config.toml | grep -qE 'codex_hooks[[:space:]]*=[[:space:]]*false'; then
    # Flip false to true (only uncommented lines)
    sed -i.bak -E 's/^([^#]*codex_hooks[[:space:]]*=[[:space:]]*)false/\1true/' .codex/config.toml
    rm -f .codex/config.toml.bak
    echo "Set codex_hooks = true in existing config.toml"
  elif grep -v '^[[:space:]]*#' .codex/config.toml | grep -q 'codex_hooks[[:space:]]*=[[:space:]]*true'; then
    echo "config.toml already has codex_hooks = true — skipping"
  elif grep -q '^\[features\]' .codex/config.toml; then
    # [features] table exists but no codex_hooks — insert after it (awk for macOS compat)
    awk '/^\[features\]/{print; print "codex_hooks = true"; next}1' .codex/config.toml > .codex/config.toml.tmp
    mv .codex/config.toml.tmp .codex/config.toml
    echo "Added codex_hooks = true to existing [features] table"
  else
    # No [features] table at all — append new section
    printf '\n[features]\ncodex_hooks = true\n' >> .codex/config.toml
    echo "Added [features] codex_hooks = true to config.toml"
  fi
else
  cp "$SCRIPT_DIR/.codex/config.toml" .codex/
  echo "Created .codex/config.toml"
fi

# hooks.json — back up if exists, then install
if [ -f ".codex/hooks.json" ]; then
  cp .codex/hooks.json ".codex/hooks.json.bak.$(date +%s)"
  echo "Backed up existing hooks.json"
fi
cp "$SCRIPT_DIR/.codex/hooks.json" .codex/
echo "Installed .codex/hooks.json"

# Hook scripts — always overwrite (these are ours)
cp "$SCRIPT_DIR/.codex/hooks/"*.sh .codex/hooks/
chmod +x .codex/hooks/*.sh
echo "Installed hook scripts"

# Repo-scoped Codex skills
install_repo_skill sdlc
install_repo_skill adlc

echo ""
echo "SDLC Wizard for Codex installed."
echo "Recommended start: 'codex --full-auto' for low-friction SDLC inside the repo guardrails."
echo "Use plain 'codex' instead if you want more manual confirmation."
echo "Repo-scoped skills will be available in a fresh Codex session: '\$sdlc' and '\$adlc'."
echo "Auth-heavy note: for Windows / WAM / MFA or other live sign-in flows, the prompt itself stays user-owned."
echo "This wizard still owns command shape, checks, and the verify/resume steps after you complete sign-in."
echo "If auth, license, tenant, or permission state decides what work is possible, add a repo-local doctor / check-capability / Test-*Access helper."
