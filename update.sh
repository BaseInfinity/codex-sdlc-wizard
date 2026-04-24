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

print_help() {
    cat <<'EOF'
Usage: update.sh [check-only] [force-all]

Modes:
  check-only   Show the selective update plan without changing files
  force-all    Replace customized wizard-managed files instead of skipping them
EOF
}

CHECK_ONLY=false
FORCE_ALL=false
CODEX_HOME_DIR="${CODEX_HOME:-$HOME/.codex}"
SKILLS_ROOT="$CODEX_HOME_DIR/skills"
SKILLS_BACKUP_ROOT="$CODEX_HOME_DIR/backups/skills"
CORE_SKILLS=("sdlc" "feedback" "setup-wizard" "update-wizard")
LEGACY_SKILLS=("codex-sdlc:sdlc")

for arg in "$@"; do
    case "$arg" in
        check-only|--check-only) CHECK_ONLY=true ;;
        force-all|--force-all|--force) FORCE_ALL=true ;;
        --help|-h) print_help; exit 0 ;;
        *)
            echo "Unknown argument: $arg" >&2
            print_help >&2
            exit 1
            ;;
    esac
done

is_generated_doc() {
    case "$1" in
        AGENTS.md|SDLC.md|TESTING.md|ARCHITECTURE.md) return 0 ;;
        *) return 1 ;;
    esac
}

ensure_parent_dir() {
    local target="$1"
    local target_dir
    target_dir="$(dirname "$target")"
    if [ "$target_dir" != "." ]; then
        mkdir -p "$target_dir"
    fi
}

copy_static_file() {
    local source_rel="$1"
    local target_rel="${2:-$1}"
    local source_path="$SCRIPT_DIR/$source_rel"

    if [ ! -f "$source_path" ]; then
        echo "Error: expected wizard file is missing: $source_rel" >&2
        exit 1
    fi

    ensure_parent_dir "$target_rel"
    cp "$source_path" "$target_rel"

    case "$target_rel" in
        *.sh) chmod +x "$target_rel" ;;
    esac
}

repair_hooks_bundle() {
    ensure_parent_dir ".codex/hooks.json"
    ensure_parent_dir ".codex/hooks/dummy"

    if [ "$IS_WINDOWS" = "true" ]; then
        copy_static_file ".codex/windows-hooks.json" ".codex/hooks.json"
        copy_static_file ".codex/hooks/git-guard.ps1"
        copy_static_file ".codex/hooks/session-start.ps1"
    else
        copy_static_file ".codex/unix-hooks.json" ".codex/hooks.json"
        copy_static_file ".codex/hooks/bash-guard.sh"
        copy_static_file ".codex/hooks/session-start.sh"
    fi
}

repair_managed_file() {
    local relative_path="$1"

    case "$relative_path" in
        .codex/hooks.json)
            repair_hooks_bundle
            ;;
        .codex/config.toml)
            merge_codex_config_profile ".codex/config.toml" "$MODEL_PROFILE"
            ;;
        *)
            copy_static_file "$relative_path"
            ;;
    esac
}

config_needs_repair() {
    codex_config_needs_profile_repair ".codex/config.toml" "$MODEL_PROFILE"
}

repair_skill() {
    local skill_name="$1"
    local source_path="$SCRIPT_DIR/skills/$skill_name"
    local target_path="$SKILLS_ROOT/$skill_name"

    if [ ! -d "$source_path" ]; then
        echo "Error: expected wizard skill is missing: skills/$skill_name" >&2
        exit 1
    fi

    mkdir -p "$SKILLS_ROOT"
    if [ -d "$target_path" ]; then
        mkdir -p "$SKILLS_BACKUP_ROOT"
        cp -R "$target_path" "$SKILLS_BACKUP_ROOT/$skill_name.bak.$(date +%s)"
        rm -rf "$target_path"
    fi

    cp -R "$source_path" "$SKILLS_ROOT/"
}

remove_legacy_skill() {
    local legacy_name="$1"
    local target_path="$SKILLS_ROOT/$legacy_name"

    [ -d "$target_path" ] || return 0

    mkdir -p "$SKILLS_BACKUP_ROOT"
    cp -R "$target_path" "$SKILLS_BACKUP_ROOT/$legacy_name.bak.$(date +%s)"
    rm -rf "$target_path"
}

restore_skipped_hashes() {
    local manifest_path=".codex-sdlc/manifest.json"
    local skipped_hashes_json="$1"

    if [ "$skipped_hashes_json" = "{}" ] || [ ! -f "$manifest_path" ]; then
        return 0
    fi

    MANIFEST_PATH="$manifest_path" SKIPPED_HASHES_JSON="$skipped_hashes_json" node - <<'NODE'
const fs = require("fs");

const manifestPath = process.env.MANIFEST_PATH;
const skippedHashes = JSON.parse(process.env.SKIPPED_HASHES_JSON || "{}");
const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));

manifest.managed_files = manifest.managed_files || {};
for (const [relativePath, expectedHash] of Object.entries(skippedHashes)) {
  manifest.managed_files[relativePath] = expectedHash;
}

fs.writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);
NODE
}

CURRENT_VERSION="$(tr -d '[:space:]' < "$SCRIPT_DIR/UPSTREAM_VERSION" 2>/dev/null || true)"
CHECK_JSON="$(bash "$SCRIPT_DIR/check.sh")"
REPO_STATE="$(printf '%s' "$CHECK_JSON" | json_get_stdin 'data.repo_state || ""')"
INSTALLED_VERSION="$(printf '%s' "$CHECK_JSON" | json_get_stdin 'data.adapter_version || ""')"
BROKEN_REASON="$(printf '%s' "$CHECK_JSON" | json_get_stdin 'data.reason || ""')"
MODEL_PROFILE="$(json_get_file ".codex-sdlc/manifest.json" 'data.model_profile?.selected_profile || ""')"
[ -n "$MODEL_PROFILE" ] || MODEL_PROFILE="$(json_get_file ".codex-sdlc/model-profile.json" 'data.selected_profile || ""')"
[ -n "$MODEL_PROFILE" ] || MODEL_PROFILE="maximum"

case "$MODEL_PROFILE" in
    mixed|maximum) ;;
    *) MODEL_PROFILE="maximum" ;;
esac

if [ "$REPO_STATE" != "initialized" ]; then
    echo "Update cannot continue: repo is uninitialized (${BROKEN_REASON:-unknown})."
    echo "Run \$setup-wizard or npx codex-sdlc-wizard setup first."
    exit 1
fi

STATUS_LINES=()
while IFS= read -r status_line; do
    STATUS_LINES+=("$status_line")
done < <(
    UPDATE_CHECK_JSON="$CHECK_JSON" node -e '
const data = JSON.parse(process.env.UPDATE_CHECK_JSON || "{}");

for (const [relativePath, info] of Object.entries(data.managed_files || {}).sort((a, b) => a[0].localeCompare(b[0]))) {
  process.stdout.write(`${relativePath}\t${info.status || ""}\n`);
}
'
)

declare -a PLAN_LINES=()
declare -a STATIC_REPAIRS=()
declare -a SKILL_REPAIRS=()
declare -a LEGACY_SKILL_REMOVALS=()
declare -a SKIPPED_CUSTOMIZED_PATHS=()
CHANGES_PENDING=false
RUN_REGENERATE=false
REGENERATE_FORCE=false

array_contains() {
    local needle="$1"
    shift
    local item

    for item in "$@"; do
        if [ "$item" = "$needle" ]; then
            return 0
        fi
    done

    return 1
}

queue_static_repair() {
    local relative_path="$1"
    if [ "${#STATIC_REPAIRS[@]}" -eq 0 ] || ! array_contains "$relative_path" "${STATIC_REPAIRS[@]}"; then
        STATIC_REPAIRS+=("$relative_path")
    fi
}

queue_skill_repair() {
    local skill_name="$1"
    if [ "${#SKILL_REPAIRS[@]}" -eq 0 ] || ! array_contains "$skill_name" "${SKILL_REPAIRS[@]}"; then
        SKILL_REPAIRS+=("$skill_name")
    fi
}

queue_legacy_skill_removal() {
    local legacy_name="$1"
    if [ "${#LEGACY_SKILL_REMOVALS[@]}" -eq 0 ] || ! array_contains "$legacy_name" "${LEGACY_SKILL_REMOVALS[@]}"; then
        LEGACY_SKILL_REMOVALS+=("$legacy_name")
    fi
}

for line in "${STATUS_LINES[@]}"; do
    IFS=$'\t' read -r relative_path status <<< "$line"
    [ -n "$relative_path" ] || continue

    action="keep"
    case "$status" in
        match)
            if [ "$relative_path" = ".codex/config.toml" ] && config_needs_repair; then
                action="merge managed model/profile settings"
                CHANGES_PENDING=true
                RUN_REGENERATE=true
                queue_static_repair "$relative_path"
            else
                action="keep"
            fi
            ;;
        missing|"drift / broken")
            action="repair"
            CHANGES_PENDING=true
            RUN_REGENERATE=true
            if ! is_generated_doc "$relative_path"; then
                queue_static_repair "$relative_path"
            fi
            ;;
        customized)
            if [ "$relative_path" = ".codex/config.toml" ] && config_needs_repair; then
                action="merge managed model/profile settings"
                CHANGES_PENDING=true
                RUN_REGENERATE=true
                queue_static_repair "$relative_path"
            elif [ "$FORCE_ALL" = "true" ]; then
                action="replace (force-all)"
                CHANGES_PENDING=true
                RUN_REGENERATE=true
                if is_generated_doc "$relative_path"; then
                    REGENERATE_FORCE=true
                else
                    queue_static_repair "$relative_path"
                fi
            else
                action="skip (preserve customization)"
                SKIPPED_CUSTOMIZED_PATHS+=("$relative_path")
            fi
            ;;
        *)
            action="inspect"
            ;;
    esac

    PLAN_LINES+=("$relative_path|$status|$action")
done

for skill_name in "${CORE_SKILLS[@]}"; do
    skill_status="present"
    skill_action="keep"

    if [ ! -f "$SKILLS_ROOT/$skill_name/SKILL.md" ]; then
        skill_status="missing"
        skill_action="install"
        CHANGES_PENDING=true
        queue_skill_repair "$skill_name"
    elif [ "$FORCE_ALL" = "true" ]; then
        skill_status="present"
        skill_action="refresh (force-all)"
        CHANGES_PENDING=true
        queue_skill_repair "$skill_name"
    fi

    PLAN_LINES+=("skills/$skill_name|$skill_status|$skill_action")
done

for legacy_spec in "${LEGACY_SKILLS[@]}"; do
    IFS=':' read -r legacy_name canonical_name <<< "$legacy_spec"
    [ -n "$legacy_name" ] || continue

    if [ -d "$SKILLS_ROOT/$legacy_name" ]; then
        PLAN_LINES+=("skills/$legacy_name|legacy|remove (canonical: $canonical_name)")
        CHANGES_PENDING=true
        queue_legacy_skill_removal "$legacy_name"
    fi
done

SKIPPED_CUSTOM_HASHES_JSON="{}"
if [ "${#SKIPPED_CUSTOMIZED_PATHS[@]}" -gt 0 ]; then
    SKIPPED_PATHS="$(
        printf '%s\n' "${SKIPPED_CUSTOMIZED_PATHS[@]}"
    )"
    SKIPPED_CUSTOM_HASHES_JSON="$(
        UPDATE_CHECK_JSON="$CHECK_JSON" UPDATE_SKIPPED_PATHS="$SKIPPED_PATHS" node -e '
const data = JSON.parse(process.env.UPDATE_CHECK_JSON || "{}");
const skippedPaths = (process.env.UPDATE_SKIPPED_PATHS || "")
  .split(/\r?\n/)
  .map((value) => value.trim())
  .filter(Boolean);
const skippedPathSet = new Set(skippedPaths);
const skipped = {};

for (const [relativePath, info] of Object.entries(data.managed_files || {})) {
  if (skippedPathSet.has(relativePath) && info && info.expected_hash) {
    skipped[relativePath] = info.expected_hash;
  }
}

process.stdout.write(JSON.stringify(skipped));
'
    )"
fi

echo "Codex SDLC update"
echo "Installed version: ${INSTALLED_VERSION:-unknown}"
echo "Available version: ${CURRENT_VERSION:-unknown}"
echo "Package boundary: this updates repo artifacts using the package you invoked; use 'npx codex-sdlc-wizard@latest update' to consume the newest npm release."
echo ""
echo "Plan:"
for plan_line in "${PLAN_LINES[@]}"; do
    IFS='|' read -r relative_path status action <<< "$plan_line"
    echo "- $relative_path: $status -> $action"
done

if [ "$CHECK_ONLY" = "true" ]; then
    echo ""
    echo "Check only: no changes applied."
    exit 0
fi

if [ "$CHANGES_PENDING" = "false" ]; then
    echo ""
    echo "No changes applied."
    exit 0
fi

echo ""
echo "Applying planned updates..."
if [ "${#STATIC_REPAIRS[@]}" -gt 0 ]; then
    for relative_path in "${STATIC_REPAIRS[@]}"; do
        repair_managed_file "$relative_path"
        echo "Applied: $relative_path"
    done
fi

if [ "${#SKILL_REPAIRS[@]}" -gt 0 ]; then
    for skill_name in "${SKILL_REPAIRS[@]}"; do
        repair_skill "$skill_name"
        echo "Applied: skills/$skill_name"
    done
fi

if [ "${#LEGACY_SKILL_REMOVALS[@]}" -gt 0 ]; then
    for legacy_name in "${LEGACY_SKILL_REMOVALS[@]}"; do
        remove_legacy_skill "$legacy_name"
        echo "Removed legacy skill: skills/$legacy_name"
    done
fi

if [ "$RUN_REGENERATE" = "true" ]; then
    if [ "$REGENERATE_FORCE" = "true" ]; then
        bash "$SCRIPT_DIR/setup.sh" regenerate --force
    else
        bash "$SCRIPT_DIR/setup.sh" regenerate
    fi
fi

if [ "$FORCE_ALL" = "false" ] && [ "$RUN_REGENERATE" = "true" ]; then
    restore_skipped_hashes "$SKIPPED_CUSTOM_HASHES_JSON"
fi

echo ""
echo "Update complete."
