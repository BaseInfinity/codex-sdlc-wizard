#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MODEL_PROFILE="mixed"
WIZARD_VERSION="$(jq -r '.version // "unknown"' "$SCRIPT_DIR/package.json" 2>/dev/null || echo unknown)"

while [ $# -gt 0 ]; do
  case "$1" in
    --model-profile)
      shift
      if [ $# -eq 0 ]; then
        echo "Missing value for --model-profile (expected: mixed or maximum)" >&2
        exit 1
      fi
      MODEL_PROFILE="$1"
      ;;
    --model-profile=*)
      MODEL_PROFILE="${1#*=}"
      ;;
  esac
  shift
done

case "$MODEL_PROFILE" in
  mixed|maximum) ;;
  *)
    echo "Unsupported model profile: $MODEL_PROFILE (expected: mixed or maximum)" >&2
    exit 1
    ;;
esac

print_feedback_guidance() {
  local command_name="$1"
  local failure_point="$2"
  local repo_shape="${3:-unknown}"

  echo ""
  echo "Likely wizard-level failure detected."
  echo "Report bugs or improvements back to codex-sdlc-wizard."
  echo "No issue will be posted automatically."
  echo "Issue-ready details:"
  echo "  wizard version: $WIZARD_VERSION"
  echo "  command: $command_name"
  echo "  repo shape: $repo_shape"
  echo "  failure point: $failure_point"
}

require_bundle_file() {
  local path="$1"
  local label="$2"
  if [ ! -f "$path" ]; then
    print_feedback_guidance "install" "missing bundled runtime file: $label" "unknown"
    exit 1
  fi
}

require_bundle_file "$SCRIPT_DIR/AGENTS.md" "AGENTS.md"
require_bundle_file "$SCRIPT_DIR/.codex/config.toml" ".codex/config.toml"
require_bundle_file "$SCRIPT_DIR/.codex/hooks.json" ".codex/hooks.json"
require_bundle_file "$SCRIPT_DIR/.codex/hooks/bash-guard.sh" ".codex/hooks/bash-guard.sh"
require_bundle_file "$SCRIPT_DIR/.codex/hooks/sdlc-prompt-check.sh" ".codex/hooks/sdlc-prompt-check.sh"
require_bundle_file "$SCRIPT_DIR/.codex/hooks/session-start.sh" ".codex/hooks/session-start.sh"
require_bundle_file "$SCRIPT_DIR/.agents/skills/sdlc/SKILL.md" ".agents/skills/sdlc/SKILL.md"
require_bundle_file "$SCRIPT_DIR/.agents/skills/adlc/SKILL.md" ".agents/skills/adlc/SKILL.md"

write_model_profile() {
  mkdir -p .codex-sdlc
  cat > .codex-sdlc/model-profile.json <<EOF
{
  "selected_profile": "$MODEL_PROFILE",
  "profiles": {
    "mixed": {
      "main_model": "gpt-5.4-mini",
      "main_reasoning": "medium",
      "review_model": "gpt-5.4",
      "review_reasoning": "xhigh",
      "tradeoff": "Faster and more token-efficient for routine work, with xhigh review as the backstop."
    },
    "maximum": {
      "main_model": "gpt-5.4",
      "main_reasoning": "xhigh",
      "review_model": "gpt-5.4",
      "review_reasoning": "xhigh",
      "tradeoff": "Higher latency and token usage in exchange for maximum stability and depth."
    }
  },
  "policy": {
    "high_confidence_threshold_percent": 95,
    "low_confidence_rule": "Research more first. If confidence stays below 95%, escalate review to xhigh. Use the maximum profile for abstract, complex, or high-blast-radius work."
  }
}
EOF
  echo "Wrote .codex-sdlc/model-profile.json ($MODEL_PROFILE)"
}

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
write_model_profile

echo ""
echo "SDLC Wizard for Codex installed."
echo "Recommended start: 'codex --full-auto' for low-friction SDLC inside the repo guardrails."
echo "Use plain 'codex' instead if you want more manual confirmation."
echo "Model profile: '$MODEL_PROFILE'."
echo "  - mixed: gpt-5.4-mini main pass + gpt-5.4 xhigh review for better speed, lower latency, and lower token usage."
echo "  - maximum: gpt-5.4 xhigh throughout for maximum stability and the most thorough \"ultimate mode\"."
echo "If confidence drops below 95%, research more first. If it still stays below 95%, escalate review to xhigh."
echo "Repo-scoped skills are still a work in progress. Today the supported public workflow skill is '\$sdlc'."
echo "Future repo-scoped skills like 'gdlc' and 'rdlc' are planned next."
echo "Auth-heavy note: for Windows / WAM / MFA or other live sign-in flows, the prompt itself stays user-owned."
echo "This wizard still owns command shape, checks, and the verify/resume steps after you complete sign-in."
echo "If auth, license, tenant, or permission state decides what work is possible, add a repo-local doctor / check-capability / Test-*Access helper."
