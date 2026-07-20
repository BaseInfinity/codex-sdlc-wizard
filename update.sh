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
CORE_SKILLS=("feedback" "setup-wizard" "update-wizard")
COLLIDING_GLOBAL_SKILLS=("sdlc:repo-scoped .agents/skills/sdlc")
LEGACY_SKILLS=("codex-sdlc:sdlc")
LEGACY_MODEL_POLICY_SDLC_SKILL_HASH="sha256:c2c280c2b0edf97538c674bf131eec06f0b6a3b50f4d56924c929f6bd0e509df"
LEGACY_FEEDBACK_SKILL_HASH="sha256:cdda0e9e12b764154a44c91f8de352138d85ce18f491972099fd332301b98ca1"
LEGACY_SETUP_WIZARD_SKILL_HASH="sha256:9e32cf8acb99ad5876e86e561f846e5b2542f12c26b85d08566a38589ee6ccc7"
LEGACY_UPDATE_WIZARD_SKILL_HASH="sha256:82696ee709eafdeef3f35def96c9179c485b368d300148326b49560d35262aad"

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
        AGENTS.md|SDLC.md|TESTING.md|ARCHITECTURE.md|GOALS.md) return 0 ;;
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
    copy_static_file ".codex/hooks/git-guard.cjs"
    copy_static_file ".codex/hooks/session-start.cjs"
    copy_static_file ".codex/hooks/compact-guard.cjs"
    rm -f .codex/hooks/git-guard.js .codex/hooks/session-start.js

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
        .codex/hooks.json|.codex/hooks/git-guard.js|.codex/hooks/session-start.js)
            repair_hooks_bundle
            ;;
        .codex/config.toml)
            merge_codex_config_profile ".codex/config.toml" "$MODEL_PROFILE"
            ;;
        .codex-sdlc/model-profile.json)
            write_model_profile_metadata ".codex-sdlc/model-profile.json" "$MODEL_PROFILE"
            ;;
        *)
            copy_static_file "$relative_path"
            ;;
    esac
}

manifest_needs_mcp_browser_policy_refresh() {
    local manifest_path=".codex-sdlc/manifest.json"
    local live_scan live_tooling live_profile_policy manifest_tooling manifest_profile_policy

    [ -f "$manifest_path" ] || return 1

    live_scan=$(bash "$SCRIPT_DIR/lib/scan.sh" 2>/dev/null || true)
    [ -n "$live_scan" ] || return 1

    live_tooling=$(printf '%s' "$live_scan" | json_get_stdin 'data.mcp_browser_tooling || ""')
    live_profile_policy=$(printf '%s' "$live_scan" | json_get_stdin 'data.mcp_browser_profile_policy || ""')
    [ -n "$live_tooling" ] || return 1
    [ -n "$live_profile_policy" ] || return 1

    manifest_tooling=$(json_get_file "$manifest_path" 'data.scan?.mcp_browser_tooling || data.resolved_values?.mcp_browser_tooling || ""')
    manifest_profile_policy=$(json_get_file "$manifest_path" 'data.scan?.mcp_browser_profile_policy || data.resolved_values?.mcp_browser_profile_policy || ""')

    [ "$manifest_tooling" != "$live_tooling" ] || [ "$manifest_profile_policy" != "$live_profile_policy" ]
}

config_needs_repair() {
    codex_config_needs_profile_repair ".codex/config.toml" "$MODEL_PROFILE"
}

file_sha256() {
    local file_path="$1"

    FILE_PATH="$file_path" node -e '
const crypto = require("crypto");
const fs = require("fs");
const content = fs.readFileSync(process.env.FILE_PATH, "utf8").replace(/\r\n/g, "\n");
const hash = crypto.createHash("sha256").update(content).digest("hex");
process.stdout.write(`sha256:${hash}`);
'
}

legacy_core_skill_hash() {
    case "$1" in
        feedback) printf '%s\n' "$LEGACY_FEEDBACK_SKILL_HASH" ;;
        setup-wizard) printf '%s\n' "$LEGACY_SETUP_WIZARD_SKILL_HASH" ;;
        update-wizard) printf '%s\n' "$LEGACY_UPDATE_WIZARD_SKILL_HASH" ;;
        *) return 1 ;;
    esac
}

skill_support_files_match_bundle() {
    local skill_name="$1"
    local source_path="$SCRIPT_DIR/skill-sources/$skill_name"
    local target_path="$SKILLS_ROOT/$skill_name"

    SOURCE_PATH="$source_path" TARGET_PATH="$target_path" node <<'NODE'
const fs = require("fs");
const path = require("path");

function files(root, relative = "") {
  const current = path.join(root, relative);
  const entries = fs.readdirSync(current, { withFileTypes: true });
  return entries.flatMap((entry) => {
    const child = path.join(relative, entry.name);
    return entry.isDirectory() ? files(root, child) : [child.split(path.sep).join("/")];
  });
}

const sourceRoot = process.env.SOURCE_PATH;
const targetRoot = process.env.TARGET_PATH;
const sourceFiles = files(sourceRoot).filter((file) => file !== "SKILL.template.md").sort();
const targetFiles = files(targetRoot).filter((file) => file !== "SKILL.md").sort();

if (JSON.stringify(sourceFiles) !== JSON.stringify(targetFiles)) process.exit(1);
for (const relativePath of sourceFiles) {
  const source = fs.readFileSync(path.join(sourceRoot, relativePath), "utf8").replace(/\r\n/g, "\n");
  const target = fs.readFileSync(path.join(targetRoot, relativePath), "utf8").replace(/\r\n/g, "\n");
  if (source !== target) process.exit(1);
}
NODE
}

matches_legacy_core_skill() {
    local skill_name="$1"
    local expected_hash
    local skill_path="$SKILLS_ROOT/$skill_name/SKILL.md"

    expected_hash="$(legacy_core_skill_hash "$skill_name")" || return 1
    [ -f "$skill_path" ] || return 1
    [ "$(file_sha256 "$skill_path")" = "$expected_hash" ] || return 1
    skill_support_files_match_bundle "$skill_name"
}

matches_legacy_model_policy_sdlc_skill() {
    local skill_path=".agents/skills/sdlc/SKILL.md"

    [ -f "$skill_path" ] || return 1
    [ "$(file_sha256 "$skill_path")" = "$LEGACY_MODEL_POLICY_SDLC_SKILL_HASH" ]
}

is_model_policy_static_surface() {
    case "$1" in
        SDLC-LOOP.md|START-SDLC.md|.agents/skills/sdlc/SKILL.md) return 0 ;;
        *) return 1 ;;
    esac
}

repair_skill() {
    local skill_name="$1"
    local source_path="$SCRIPT_DIR/skill-sources/$skill_name"
    local source_template="$SCRIPT_DIR/skill-sources/$skill_name/SKILL.template.md"
    local target_path="$SKILLS_ROOT/$skill_name"

    if [ ! -d "$source_path" ] || [ ! -f "$source_template" ]; then
        echo "Error: expected wizard skill source is missing: skill-sources/$skill_name" >&2
        exit 1
    fi

    mkdir -p "$SKILLS_ROOT"
    if [ -d "$target_path" ]; then
        mkdir -p "$SKILLS_BACKUP_ROOT"
        cp -R "$target_path" "$SKILLS_BACKUP_ROOT/$skill_name.bak.$(date +%s)"
        rm -rf "$target_path"
    fi

    cp -R "$source_path" "$SKILLS_ROOT/"
    mv "$target_path/SKILL.template.md" "$target_path/SKILL.md"
}

remove_legacy_skill() {
    local legacy_name="$1"
    local target_path="$SKILLS_ROOT/$legacy_name"

    [ -d "$target_path" ] || return 0

    mkdir -p "$SKILLS_BACKUP_ROOT"
    cp -R "$target_path" "$SKILLS_BACKUP_ROOT/$legacy_name.bak.$(date +%s)"
    rm -rf "$target_path"
}

global_skill_matches_bundle() {
    local skill_name="$1"
    local bundled_path="$SCRIPT_DIR/skill-sources/$skill_name"
    local target_path="$SKILLS_ROOT/$skill_name"

    [ -d "$bundled_path" ] || return 1
    [ -d "$target_path" ] || return 1

    [ -f "$bundled_path/SKILL.template.md" ] || return 1
    [ -f "$target_path/SKILL.md" ] || return 1
    diff -q "$bundled_path/SKILL.template.md" "$target_path/SKILL.md" >/dev/null 2>&1 \
        && skill_support_files_match_bundle "$skill_name"
}

remove_colliding_global_skill() {
    local skill_name="$1"
    local target_path="$SKILLS_ROOT/$skill_name"

    [ -d "$target_path" ] || return 0

    mkdir -p "$SKILLS_BACKUP_ROOT"
    cp -R "$target_path" "$SKILLS_BACKUP_ROOT/$skill_name.bak.$(date +%s)"
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
  if (expectedHash === null) {
    delete manifest.managed_files[relativePath];
  } else {
    manifest.managed_files[relativePath] = expectedHash;
  }
}

fs.writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);
NODE
}

record_model_policy_migration() {
    local manifest_path=".codex-sdlc/manifest.json"

    MANIFEST_PATH="$manifest_path" MODEL_POLICY_SCHEMA_VERSION_SELECTED="$MODEL_POLICY_SCHEMA_VERSION" node - <<'NODE'
const fs = require("fs");

const manifestPath = process.env.MANIFEST_PATH;
const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
manifest.model_profile = manifest.model_profile || {};
manifest.model_profile.policy_schema_version = Number(process.env.MODEL_POLICY_SCHEMA_VERSION_SELECTED);
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
MODEL_PROFILE_DEFAULTED=false
if [ -z "$MODEL_PROFILE" ]; then
    MODEL_PROFILE="maximum"
    MODEL_PROFILE_DEFAULTED=true
fi

case "$MODEL_PROFILE" in
    mixed|maximum) ;;
    *)
        MODEL_PROFILE="maximum"
        MODEL_PROFILE_DEFAULTED=true
        ;;
esac

MODEL_PROFILE_METADATA_STATUS="$(printf '%s' "$CHECK_JSON" | json_get_stdin 'data.managed_files?.[".codex-sdlc/model-profile.json"]?.status || ""')"
MANIFEST_MODEL_POLICY_SCHEMA_VERSION="$(json_get_file ".codex-sdlc/manifest.json" 'data.model_profile?.policy_schema_version || ""')"
MODEL_POLICY_SCHEMA_MIGRATION=false
RECORD_MODEL_POLICY_MIGRATION=false
case "$MANIFEST_MODEL_POLICY_SCHEMA_VERSION" in
    ''|*[!0-9]*) MODEL_POLICY_SCHEMA_MIGRATION=true ;;
    *)
        if [ "$MANIFEST_MODEL_POLICY_SCHEMA_VERSION" -lt "$MODEL_POLICY_SCHEMA_VERSION" ]; then
            MODEL_POLICY_SCHEMA_MIGRATION=true
        fi
        ;;
esac
MODEL_PROFILE_MIGRATION="$MODEL_PROFILE_DEFAULTED"
if [ "$MODEL_PROFILE_METADATA_STATUS" = "missing" ]; then
    MODEL_PROFILE_MIGRATION=true
elif [ "$MODEL_PROFILE_METADATA_STATUS" = "match" ] && model_profile_metadata_needs_refresh ".codex-sdlc/model-profile.json" "$MODEL_PROFILE"; then
    MODEL_PROFILE_MIGRATION=true
elif [ "$MODEL_PROFILE_METADATA_STATUS" = "customized" ] && [ "$MODEL_POLICY_SCHEMA_MIGRATION" = "true" ] && model_profile_metadata_is_legacy ".codex-sdlc/model-profile.json"; then
    MODEL_PROFILE_MIGRATION=true
    RECORD_MODEL_POLICY_MIGRATION=true
fi

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
declare -a COLLIDING_SKILL_REMOVALS=()
declare -a LEGACY_SKILL_REMOVALS=()
declare -a SKIPPED_CUSTOMIZED_PATHS=()
declare -a SKIPPED_UNTRACKED_PATHS=()
declare -a MATCHED_GENERATED_DOCS=()
declare -a REGENERATE_EXISTING_DOCS=()
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

queue_colliding_skill_removal() {
    local skill_name="$1"
    if [ "${#COLLIDING_SKILL_REMOVALS[@]}" -eq 0 ] || ! array_contains "$skill_name" "${COLLIDING_SKILL_REMOVALS[@]}"; then
        COLLIDING_SKILL_REMOVALS+=("$skill_name")
    fi
}

queue_legacy_skill_removal() {
    local legacy_name="$1"
    if [ "${#LEGACY_SKILL_REMOVALS[@]}" -eq 0 ] || ! array_contains "$legacy_name" "${LEGACY_SKILL_REMOVALS[@]}"; then
        LEGACY_SKILL_REMOVALS+=("$legacy_name")
    fi
}

queue_regenerate_existing_doc() {
    local relative_path="$1"
    if [ "${#REGENERATE_EXISTING_DOCS[@]}" -eq 0 ] || ! array_contains "$relative_path" "${REGENERATE_EXISTING_DOCS[@]}"; then
        REGENERATE_EXISTING_DOCS+=("$relative_path")
    fi
}

for line in "${STATUS_LINES[@]}"; do
    IFS=$'\t' read -r relative_path status <<< "$line"
    [ -n "$relative_path" ] || continue

    action="keep"
    case "$status" in
        match)
            if [ "$relative_path" = ".codex-sdlc/model-profile.json" ] && [ "$MODEL_PROFILE_MIGRATION" = "true" ]; then
                action="refresh legacy model profile metadata"
                CHANGES_PENDING=true
                RUN_REGENERATE=true
                queue_static_repair "$relative_path"
            elif [ "$relative_path" = "AGENTS.md" ] && [ "$MODEL_PROFILE_MIGRATION" = "true" ]; then
                action="refresh generated model policy"
                CHANGES_PENDING=true
                RUN_REGENERATE=true
                queue_regenerate_existing_doc "$relative_path"
            elif [ "$MODEL_PROFILE_MIGRATION" = "true" ] && is_model_policy_static_surface "$relative_path"; then
                action="refresh model policy"
                CHANGES_PENDING=true
                RUN_REGENERATE=true
                queue_static_repair "$relative_path"
            elif [ "$relative_path" = ".codex/config.toml" ] && config_needs_repair; then
                action="merge managed model/profile settings"
                CHANGES_PENDING=true
                RUN_REGENERATE=true
                queue_static_repair "$relative_path"
            else
                action="keep"
                if is_generated_doc "$relative_path"; then
                    MATCHED_GENERATED_DOCS+=("$relative_path")
                fi
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

if [ "$RECORD_MODEL_POLICY_MIGRATION" = "true" ]; then
    PLAN_LINES+=(".codex-sdlc/manifest.json|model policy schema $MANIFEST_MODEL_POLICY_SCHEMA_VERSION|record model policy migration completion")
    CHANGES_PENDING=true
fi

REPO_SDLC_SKILL_STATUS="$(printf '%s' "$CHECK_JSON" | json_get_stdin 'data.managed_files?.[".agents/skills/sdlc/SKILL.md"]?.status || ""')"
if [ "$MODEL_PROFILE_MIGRATION" = "true" ] && [ -z "$REPO_SDLC_SKILL_STATUS" ]; then
    if [ ! -f ".agents/skills/sdlc/SKILL.md" ]; then
        PLAN_LINES+=(".agents/skills/sdlc/SKILL.md|missing|repair")
        CHANGES_PENDING=true
        RUN_REGENERATE=true
        queue_static_repair ".agents/skills/sdlc/SKILL.md"
    elif matches_legacy_model_policy_sdlc_skill; then
        PLAN_LINES+=(".agents/skills/sdlc/SKILL.md|legacy unmodified|refresh model policy")
        CHANGES_PENDING=true
        RUN_REGENERATE=true
        queue_static_repair ".agents/skills/sdlc/SKILL.md"
    else
        PLAN_LINES+=(".agents/skills/sdlc/SKILL.md|untracked|skip (preserve customization)")
        SKIPPED_UNTRACKED_PATHS+=(".agents/skills/sdlc/SKILL.md")
    fi
fi

if manifest_needs_mcp_browser_policy_refresh; then
    PLAN_LINES+=(".codex-sdlc/manifest.json|MCP browser policy missing|refresh generated docs from live scan")
    CHANGES_PENDING=true
    RUN_REGENERATE=true
    if [ "$FORCE_ALL" = "true" ]; then
        REGENERATE_FORCE=true
    elif array_contains "ARCHITECTURE.md" "${MATCHED_GENERATED_DOCS[@]}"; then
        queue_regenerate_existing_doc "ARCHITECTURE.md"
    fi
fi

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
    elif [ "$MODEL_PROFILE_MIGRATION" = "true" ]; then
        if global_skill_matches_bundle "$skill_name"; then
            skill_status="present"
            skill_action="keep"
        elif matches_legacy_core_skill "$skill_name"; then
            skill_status="legacy unmodified"
            skill_action="refresh model policy"
            CHANGES_PENDING=true
            queue_skill_repair "$skill_name"
        else
            skill_status="customized"
            skill_action="skip (preserve customization)"
        fi
    fi

    PLAN_LINES+=("skills/$skill_name|$skill_status|$skill_action")
done

for collision_spec in "${COLLIDING_GLOBAL_SKILLS[@]}"; do
    IFS=':' read -r skill_name canonical_scope <<< "$collision_spec"
    [ -n "$skill_name" ] || continue

    if global_skill_matches_bundle "$skill_name"; then
        PLAN_LINES+=("skills/$skill_name|same-name collision|remove (canonical: $canonical_scope)")
        CHANGES_PENDING=true
        queue_colliding_skill_removal "$skill_name"
    fi
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
if [ "${#SKIPPED_CUSTOMIZED_PATHS[@]}" -gt 0 ] || [ "${#SKIPPED_UNTRACKED_PATHS[@]}" -gt 0 ]; then
    SKIPPED_PATHS="$(
        printf '%s\n' "${SKIPPED_CUSTOMIZED_PATHS[@]}"
    )"
    UNTRACKED_PATHS="$(
        printf '%s\n' "${SKIPPED_UNTRACKED_PATHS[@]}"
    )"
    SKIPPED_CUSTOM_HASHES_JSON="$(
        UPDATE_CHECK_JSON="$CHECK_JSON" UPDATE_SKIPPED_PATHS="$SKIPPED_PATHS" UPDATE_UNTRACKED_PATHS="$UNTRACKED_PATHS" node -e '
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

for (const relativePath of (process.env.UPDATE_UNTRACKED_PATHS || "").split(/\r?\n/).map((value) => value.trim()).filter(Boolean)) {
  skipped[relativePath] = null;
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

require_gpt56_codex_version

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

if [ "${#COLLIDING_SKILL_REMOVALS[@]}" -gt 0 ]; then
    for skill_name in "${COLLIDING_SKILL_REMOVALS[@]}"; do
        remove_colliding_global_skill "$skill_name"
        echo "Removed same-name global skill collision: skills/$skill_name (repo-scoped .agents/skills/sdlc is canonical)"
    done
fi

if [ "${#LEGACY_SKILL_REMOVALS[@]}" -gt 0 ]; then
    for legacy_name in "${LEGACY_SKILL_REMOVALS[@]}"; do
        remove_legacy_skill "$legacy_name"
        echo "Removed legacy skill: skills/$legacy_name"
    done
fi

if [ "$RUN_REGENERATE" = "true" ]; then
    if [ "$REGENERATE_FORCE" = "false" ] && [ "${#REGENERATE_EXISTING_DOCS[@]}" -gt 0 ]; then
        for relative_path in "${REGENERATE_EXISTING_DOCS[@]}"; do
            if [ -f "$relative_path" ]; then
                rm -f "$relative_path"
                echo "Prepared for regeneration: $relative_path"
            fi
        done
    fi

    if [ "$REGENERATE_FORCE" = "true" ]; then
        bash "$SCRIPT_DIR/setup.sh" regenerate --force
    else
        bash "$SCRIPT_DIR/setup.sh" regenerate
    fi
fi

if [ "$FORCE_ALL" = "false" ] && [ "$RUN_REGENERATE" = "true" ]; then
    restore_skipped_hashes "$SKIPPED_CUSTOM_HASHES_JSON"
fi

if [ "$RECORD_MODEL_POLICY_MIGRATION" = "true" ]; then
    record_model_policy_migration
    echo "Applied: .codex-sdlc/manifest.json (recorded model policy migration completion)"
fi

echo ""
echo "Update complete."
