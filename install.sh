#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/json-node.sh"
source "$SCRIPT_DIR/lib/codex-config.sh"
require_node

case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) IS_WINDOWS=true ;;
    *) IS_WINDOWS=false ;;
esac

MODEL_PROFILE="mixed"
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

WIZARD_VERSION="$(json_get_file "$SCRIPT_DIR/package.json" 'data.version || "unknown"')"
[ -z "$WIZARD_VERSION" ] && WIZARD_VERSION="unknown"

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

for required in \
  "AGENTS.md" \
  "SDLC-LOOP.md" \
  "START-SDLC.md" \
  "PROVE-IT.md" \
  "start-sdlc.sh" \
  "start-sdlc.ps1" \
  ".codex/config.toml" \
  ".codex/hooks.json" \
  ".codex/unix-hooks.json" \
  ".codex/windows-hooks.json" \
  ".codex/hooks/bash-guard.sh" \
  ".codex/hooks/session-start.sh" \
  ".codex/hooks/sdlc-prompt-check.sh" \
  ".codex/hooks/git-guard.ps1" \
  ".codex/hooks/session-start.ps1" \
  ".agents/skills/sdlc/SKILL.md" \
  ".agents/skills/adlc/SKILL.md"; do
  require_bundle_file "$SCRIPT_DIR/$required" "$required"
done

CODEX_HOME_DIR="${CODEX_HOME:-$HOME/.codex}"
SKILLS_ROOT="$CODEX_HOME_DIR/skills"
SKILLS_BACKUP_ROOT="$CODEX_HOME_DIR/backups/skills"

copy_if_missing() {
  local source="$1"
  local target="$2"
  local label="$3"
  if [ ! -f "$target" ]; then
    cp "$source" "$target"
    echo "Created $label"
  else
    echo "$label already exists - skipping (review manually)"
  fi
}

install_repo_skill() {
  local name="$1"
  local source="$SCRIPT_DIR/.agents/skills/$name/SKILL.md"
  local target=".agents/skills/$name/SKILL.md"

  mkdir -p "$(dirname "$target")"
  if [ -f "$target" ]; then
    echo "$target already exists - skipping (review manually)"
  else
    cp "$source" "$target"
    echo "Installed $target"
  fi
}

install_global_skill() {
  local skill_path="$1"
  local skill_name

  [ -d "$skill_path" ] || return 0

  skill_name="$(basename "$skill_path")"
  if [ -d "$SKILLS_ROOT/$skill_name" ]; then
    cp -R "$SKILLS_ROOT/$skill_name" "$SKILLS_BACKUP_ROOT/$skill_name.bak.$(date +%s)"
    rm -rf "$SKILLS_ROOT/$skill_name"
    echo "Backed up existing Codex skill: $skill_name"
  fi
  cp -R "$skill_path" "$SKILLS_ROOT/"
  echo "Installed Codex skill: $skill_name"
}

prune_legacy_global_skill() {
  local legacy_name="$1"
  local canonical_name="$2"
  local legacy_path="$SKILLS_ROOT/$legacy_name"

  [ -d "$legacy_path" ] || return 0

  mkdir -p "$SKILLS_BACKUP_ROOT"
  cp -R "$legacy_path" "$SKILLS_BACKUP_ROOT/$legacy_name.bak.$(date +%s)"
  rm -rf "$legacy_path"
  echo "Removed legacy Codex skill: $legacy_name (canonical: $canonical_name)"
}

write_model_profile() {
  mkdir -p .codex-sdlc
  cat > .codex-sdlc/model-profile.json <<EOF
{
  "selected_profile": "$MODEL_PROFILE",
  "profiles": {
    "mixed": {
      "main_model": "gpt-5.4-mini",
      "main_reasoning": "medium",
      "review_model": "gpt-5.5",
      "review_reasoning": "xhigh",
      "tradeoff": "Smaller/faster main model for routine work while keeping xhigh reasoning and xhigh review."
    },
    "maximum": {
      "main_model": "gpt-5.5",
      "main_reasoning": "xhigh",
      "review_model": "gpt-5.5",
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

copy_if_missing "$SCRIPT_DIR/AGENTS.md" "AGENTS.md" "AGENTS.md"
copy_if_missing "$SCRIPT_DIR/SDLC-LOOP.md" "SDLC-LOOP.md" "SDLC-LOOP.md"
copy_if_missing "$SCRIPT_DIR/START-SDLC.md" "START-SDLC.md" "START-SDLC.md"
copy_if_missing "$SCRIPT_DIR/PROVE-IT.md" "PROVE-IT.md" "PROVE-IT.md"

mkdir -p "$SKILLS_ROOT" "$SKILLS_BACKUP_ROOT"
for skill_path in "$SCRIPT_DIR"/skills/*; do
  install_global_skill "$skill_path"
done
prune_legacy_global_skill "codex-sdlc" "sdlc"

mkdir -p .codex/hooks

merge_codex_config_profile ".codex/config.toml" "$MODEL_PROFILE"
echo "Merged repo-local Codex config for model profile '$MODEL_PROFILE'"

if [ -f ".codex/hooks.json" ]; then
  cp .codex/hooks.json ".codex/hooks.json.bak.$(date +%s)"
  echo "Backed up existing hooks.json"
fi

cp "$SCRIPT_DIR/.codex/hooks/"*.sh .codex/hooks/
chmod +x .codex/hooks/*.sh

if [ "$IS_WINDOWS" = "true" ]; then
  cp "$SCRIPT_DIR/.codex/windows-hooks.json" .codex/hooks.json
  cp "$SCRIPT_DIR/.codex/hooks/git-guard.ps1" .codex/hooks/
  cp "$SCRIPT_DIR/.codex/hooks/session-start.ps1" .codex/hooks/
  copy_if_missing "$SCRIPT_DIR/start-sdlc.ps1" "start-sdlc.ps1" "start-sdlc.ps1"
  echo "Installed .codex/hooks.json (Windows PowerShell hooks)"
  echo "Installed PowerShell hook scripts"
else
  cp "$SCRIPT_DIR/.codex/unix-hooks.json" .codex/hooks.json
  copy_if_missing "$SCRIPT_DIR/start-sdlc.sh" "start-sdlc.sh" "start-sdlc.sh"
  chmod +x start-sdlc.sh
  echo "Installed .codex/hooks.json"
fi

echo "Installed shell hook scripts"

install_repo_skill sdlc
install_repo_skill adlc
write_model_profile

echo ""
echo "SDLC Wizard for Codex installed."
echo "Recommended start: 'codex --full-auto' for low-friction SDLC inside the repo guardrails."
echo "Use plain 'codex' instead if you want more manual confirmation."
echo "If you close or interrupt the handoff, resume with 'codex resume --full-auto' when Codex gives you a resume id."
echo "Model profile: '$MODEL_PROFILE'."
echo "  - mixed: gpt-5.4-mini main pass + gpt-5.5 xhigh review for better speed, lower latency, and lower token usage."
echo "  - maximum: gpt-5.5 xhigh throughout for maximum stability and the most thorough \"ultimate mode\"."
echo "Wrote repo-local .codex/config.toml model keys for this profile; mixed is wizard policy, not a native Codex mode."
echo "Codex loads project config only after the repo is trusted, and trusted project config overrides your user-level ~/.codex/config.toml."
echo "If confidence drops below 95%, research more first. If it still stays below 95%, escalate review to xhigh."
echo "Repo-scoped skills are still a work in progress. Today the supported public workflow skill is '\$sdlc'."
echo "Future repo-scoped skills like 'gdlc' and 'rdlc' are planned next."
echo "Auth-heavy note: for Windows / WAM / MFA or other live sign-in flows, the prompt itself stays user-owned."
echo "This wizard still owns command shape, checks, and the verify/resume steps after you complete sign-in."
echo "If auth, license, tenant, or permission state decides what work is possible, add a repo-local doctor / check-capability / Test-*Access helper."
