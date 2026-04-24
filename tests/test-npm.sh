#!/bin/bash
# npm packaging tests — keep the npx install surface working end to end

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$SCRIPT_DIR/.."
PACKAGE_JSON="$REPO_DIR/package.json"
ROADMAP="$REPO_DIR/ROADMAP.md"
JSON_HELPERS="$REPO_DIR/lib/json-node.sh"
source "$JSON_HELPERS"
require_node
PASSED=0
FAILED=0
MKTEMP_DIR="${TMPDIR:-/tmp}"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

pass() {
    echo -e "${GREEN}PASS${NC}: $1"
    PASSED=$((PASSED + 1))
}

fail() {
    echo -e "${RED}FAIL${NC}: $1"
    FAILED=$((FAILED + 1))
}

echo "=== npm Packaging Tests ==="
echo ""

test_package_metadata_exists() {
    local has_name=true
    local has_version=true
    local has_bin=true

    [ -f "$PACKAGE_JSON" ] || has_name=false
    json_has_truthy_file "$PACKAGE_JSON" 'data.name === "codex-sdlc-wizard"' || has_name=false
    json_has_truthy_file "$PACKAGE_JSON" 'typeof data.version === "string"' || has_version=false
    json_has_truthy_file "$PACKAGE_JSON" 'data.bin && data.bin["codex-sdlc-wizard"] === "bin/codex-sdlc-wizard.js"' || has_bin=false

    if [ "$has_name" = "true" ] &&
       [ "$has_version" = "true" ] &&
       [ "$has_bin" = "true" ]; then
        pass "package.json exposes the codex-sdlc-wizard CLI"
    else
        fail "package.json is missing the expected npm CLI metadata"
    fi
}

test_package_version_matches_roadmap_current_release() {
    local package_version current_state_section
    package_version=$(json_get_file "$PACKAGE_JSON" 'data.version')
    current_state_section=$(awk '
        /^## Current State$/ { in_section=1; next }
        /^## / && in_section { exit }
        in_section { print }
    ' "$ROADMAP")

    if [ -n "$package_version" ] && echo "$current_state_section" | grep -q "$package_version"; then
        pass "package.json version matches the roadmap current-release state"
    else
        fail "package.json version does not match the roadmap current-release state"
    fi
}

test_npm_pack_includes_runtime_files() {
    local pack_dir
    pack_dir=$(mktemp -d "$MKTEMP_DIR/sdlc-npm-pack.XXXXXX")
    local npm_cache
    npm_cache=$(mktemp -d "$MKTEMP_DIR/sdlc-npm-cache.XXXXXX")

    local tarball json tarball_name
    json=$(cd "$REPO_DIR" && npm_config_cache="$npm_cache" npm pack --json --pack-destination "$pack_dir" 2>/dev/null) || true
    tarball_name=$(printf '%s' "$json" | json_get_stdin 'Array.isArray(data) && data[0] ? data[0].filename : ""')

    local has_tarball=true
    local has_install=true
    local has_setup=true
    local has_hooks=true
    local has_bin=true
    local has_skill=true
    local has_openai_yaml=true
    local has_repo_sdlc_skill=true
    local has_repo_adlc_skill=true

    if [ -z "$tarball_name" ] || [ ! -f "$pack_dir/$tarball_name" ]; then
        has_tarball=false
        has_install=false
        has_setup=false
        has_hooks=false
        has_bin=false
        has_skill=false
        has_openai_yaml=false
        has_repo_sdlc_skill=false
        has_repo_adlc_skill=false
    else
        [ "$(printf '%s' "$json" | json_get_stdin 'Array.isArray(data) && data[0] && Array.isArray(data[0].files) && data[0].files.some((file) => file.path === "install.sh") ? "yes" : ""')" = "yes" ] || has_install=false
        [ "$(printf '%s' "$json" | json_get_stdin 'Array.isArray(data) && data[0] && Array.isArray(data[0].files) && data[0].files.some((file) => file.path === "setup.sh") ? "yes" : ""')" = "yes" ] || has_setup=false
        [ "$(printf '%s' "$json" | json_get_stdin 'Array.isArray(data) && data[0] && Array.isArray(data[0].files) && data[0].files.some((file) => file.path === ".codex/hooks/bash-guard.sh") ? "yes" : ""')" = "yes" ] || has_hooks=false
        [ "$(printf '%s' "$json" | json_get_stdin 'Array.isArray(data) && data[0] && Array.isArray(data[0].files) && data[0].files.some((file) => file.path === "bin/codex-sdlc-wizard.js") ? "yes" : ""')" = "yes" ] || has_bin=false
        [ "$(printf '%s' "$json" | json_get_stdin 'Array.isArray(data) && data[0] && Array.isArray(data[0].files) && data[0].files.some((file) => file.path === "SKILL.md") ? "yes" : ""')" = "yes" ] || has_skill=false
        [ "$(printf '%s' "$json" | json_get_stdin 'Array.isArray(data) && data[0] && Array.isArray(data[0].files) && data[0].files.some((file) => file.path === "agents/openai.yaml") ? "yes" : ""')" = "yes" ] || has_openai_yaml=false
        [ "$(printf '%s' "$json" | json_get_stdin 'Array.isArray(data) && data[0] && Array.isArray(data[0].files) && data[0].files.some((file) => file.path === ".agents/skills/sdlc/SKILL.md") ? "yes" : ""')" = "yes" ] || has_repo_sdlc_skill=false
        [ "$(printf '%s' "$json" | json_get_stdin 'Array.isArray(data) && data[0] && Array.isArray(data[0].files) && data[0].files.some((file) => file.path === ".agents/skills/adlc/SKILL.md") ? "yes" : ""')" = "yes" ] || has_repo_adlc_skill=false
    fi

    rm -rf "$pack_dir" "$npm_cache"

    if [ "$has_tarball" = "true" ] &&
       [ "$has_install" = "true" ] &&
       [ "$has_setup" = "true" ] &&
       [ "$has_hooks" = "true" ] &&
       [ "$has_bin" = "true" ] &&
       [ "$has_skill" = "true" ] &&
       [ "$has_openai_yaml" = "true" ] &&
       [ "$has_repo_sdlc_skill" = "true" ] &&
       [ "$has_repo_adlc_skill" = "true" ]; then
        pass "npm pack includes the CLI, installer, and skill runtime files"
    else
        fail "npm pack is missing required runtime files"
    fi
}

test_local_npx_installs_into_clean_repo() {
    local pack_dir target_repo
    pack_dir=$(mktemp -d "$MKTEMP_DIR/sdlc-npx-pack.XXXXXX")
    target_repo=$(mktemp -d "$MKTEMP_DIR/sdlc-npx-target.XXXXXX")
    local npm_cache
    npm_cache=$(mktemp -d "$MKTEMP_DIR/sdlc-npx-cache.XXXXXX")

    local json tarball_name
    json=$(cd "$REPO_DIR" && npm_config_cache="$npm_cache" npm pack --json --pack-destination "$pack_dir" 2>/dev/null) || true
    tarball_name=$(printf '%s' "$json" | json_get_stdin 'Array.isArray(data) && data[0] ? data[0].filename : ""')

    local tarball_path="$pack_dir/$tarball_name"
    local installed=true

    if [ -z "$tarball_name" ] || [ ! -f "$tarball_path" ]; then
        installed=false
    else
        printf '%s' '{"name":"install-smoke","scripts":{"test":"jest"}}' > "$target_repo/package.json"
        mkdir -p "$target_repo/src"
        (
            cd "$target_repo"
            npm_config_cache="$npm_cache" npm exec --yes --package "$tarball_path" -- codex-sdlc-wizard --yes >/dev/null 2>&1
        ) || installed=false
    fi

    [ -f "$target_repo/AGENTS.md" ] || installed=false
    [ -f "$target_repo/.codex/config.toml" ] || installed=false
    [ -f "$target_repo/.codex/hooks.json" ] || installed=false
    [ -x "$target_repo/.codex/hooks/bash-guard.sh" ] || installed=false
    [ -f "$target_repo/.agents/skills/sdlc/SKILL.md" ] || installed=false
    [ -f "$target_repo/.agents/skills/adlc/SKILL.md" ] || installed=false
    [ -f "$target_repo/.codex-sdlc/manifest.json" ] || installed=false

    rm -rf "$pack_dir" "$target_repo" "$npm_cache"

    if [ "$installed" = "true" ]; then
        pass "local npm exec defaults to adaptive setup when automation passes --yes"
    else
        fail "local npm exec did not route the default command through adaptive setup"
    fi
}

test_local_npx_setup_honors_model_profile_flag() {
    local pack_dir target_repo
    pack_dir=$(mktemp -d "$MKTEMP_DIR/sdlc-npx-pack.XXXXXX")
    target_repo=$(mktemp -d "$MKTEMP_DIR/sdlc-npx-target.XXXXXX")
    local npm_cache
    npm_cache=$(mktemp -d "$MKTEMP_DIR/sdlc-npx-cache.XXXXXX")

    local json tarball_name
    json=$(cd "$REPO_DIR" && npm_config_cache="$npm_cache" npm pack --json --pack-destination "$pack_dir" 2>/dev/null) || true
    tarball_name=$(printf '%s' "$json" | json_get_stdin 'Array.isArray(data) && data[0] ? data[0].filename : ""')

    local configured=true
    local tarball_path="$pack_dir/$tarball_name"

    if [ -z "$tarball_name" ] || [ ! -f "$tarball_path" ]; then
        configured=false
    else
        (
            cd "$target_repo"
            npm_config_cache="$npm_cache" npm exec --yes --package "$tarball_path" -- codex-sdlc-wizard setup --yes --model-profile maximum >/dev/null 2>&1
        ) || configured=false
    fi

    if [ "$configured" = "true" ]; then
        if [ ! -f "$target_repo/.codex-sdlc/model-profile.json" ] ||
           ! json_has_truthy_file "$target_repo/.codex-sdlc/model-profile.json" 'data.selected_profile === "maximum"'; then
            configured=false
        fi
    fi

    rm -rf "$pack_dir" "$target_repo" "$npm_cache"

    if [ "$configured" = "true" ]; then
        pass "local npm exec setup honors the model-profile flag"
    else
        fail "local npm exec setup did not honor the model-profile flag"
    fi
}

test_packed_tarball_scratch_smoke() {
    local pack_dir target_repo
    pack_dir=$(mktemp -d "$MKTEMP_DIR/sdlc-npx-pack.XXXXXX")
    target_repo=$(mktemp -d "$MKTEMP_DIR/sdlc-npx-target.XXXXXX")
    local npm_cache
    npm_cache=$(mktemp -d "$MKTEMP_DIR/sdlc-npx-cache.XXXXXX")

    local json tarball_name tarball_path
    json=$(cd "$REPO_DIR" && npm_config_cache="$npm_cache" npm pack --json --pack-destination "$pack_dir" 2>/dev/null) || true
    tarball_name=$(printf '%s' "$json" | json_get_stdin 'Array.isArray(data) && data[0] ? data[0].filename : ""')
    tarball_path="$pack_dir/$tarball_name"

    local valid=true
    local setup_output="" check_output="" update_output=""

    if [ -z "$tarball_name" ] || [ ! -f "$tarball_path" ]; then
        valid=false
    else
        printf '%s' '{"name":"release-smoke","scripts":{"test":"jest"}}' > "$target_repo/package.json"
        mkdir -p "$target_repo/src"

        setup_output=$(
            cd "$target_repo" && \
            npm_config_cache="$npm_cache" npm exec --yes --package "$tarball_path" -- \
                codex-sdlc-wizard setup --yes 2>&1
        ) || valid=false

        check_output=$(
            cd "$target_repo" && \
            npm_config_cache="$npm_cache" npm exec --yes --package "$tarball_path" -- \
                codex-sdlc-wizard check 2>&1
        ) || valid=false

        update_output=$(
            cd "$target_repo" && \
            npm_config_cache="$npm_cache" npm exec --yes --package "$tarball_path" -- \
                codex-sdlc-wizard update check-only 2>&1
        ) || valid=false
    fi

    [ -f "$target_repo/.codex-sdlc/manifest.json" ] || valid=false
    json_has_truthy_file "$target_repo/.codex-sdlc/manifest.json" 'typeof data.managed_files?.["AGENTS.md"] === "string" && /^sha256:[0-9a-f]{64}$/.test(data.managed_files["AGENTS.md"])' || valid=false
    echo "$setup_output" | grep -q 'Setup complete' || valid=false
    echo "$setup_output" | grep -q 'shasum: command not found' && valid=false
    echo "$check_output" | grep -q '"status": "match"' || valid=false
    echo "$update_output" | grep -Eq 'No managed files need updates|"status": "match"|match' || valid=false

    rm -rf "$pack_dir" "$target_repo" "$npm_cache"

    if [ "$valid" = "true" ]; then
        pass "packed tarball scratch smoke proves setup, check, and update on a clean repo"
    else
        fail "packed tarball scratch smoke did not prove the release surface cleanly"
    fi
}

test_cli_help_documents_bootstrap_profile_policy() {
    local output
    output=$(node "$REPO_DIR/bin/codex-sdlc-wizard.js" --help 2>&1) || true

    local valid=true
    echo "$output" | grep -qi 'mixed' || valid=false
    echo "$output" | grep -qi 'maximum' || valid=false
    echo "$output" | grep -Eqi 'setup.*maximum|bootstrap.*maximum' || valid=false
    echo "$output" | grep -Eqi 'routine work.*mixed|day-to-day.*mixed|after bootstrap.*mixed' || valid=false
    echo "$output" | grep -Eqi 'default.*adaptive setup|adaptive setup.*default' || valid=false

    if [ "$valid" = "true" ]; then
        pass "CLI help documents adaptive setup as the default plus the bootstrap profile policy"
    else
        fail "CLI help does not document the adaptive default and bootstrap-versus-routine profile policy clearly enough"
    fi
}

test_package_metadata_exists
test_package_version_matches_roadmap_current_release
test_npm_pack_includes_runtime_files
test_local_npx_installs_into_clean_repo
test_local_npx_setup_honors_model_profile_flag
test_packed_tarball_scratch_smoke
test_cli_help_documents_bootstrap_profile_policy

echo ""
echo "=== Results: $PASSED passed, $FAILED failed ==="

if [ "$FAILED" -gt 0 ]; then
    exit 1
fi
